package dev.parth.android_sign_in_kit

import android.accounts.Account
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.RequiresApi
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CreateCredentialResponse
import androidx.credentials.CreatePasswordRequest
import androidx.credentials.Credential
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.CredentialOption
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.GetPasswordOption
import androidx.credentials.PasswordCredential
import androidx.credentials.PrepareGetCredentialResponse
import androidx.credentials.PrepareGetCredentialResponse.PendingGetCredentialHandle
import androidx.credentials.exceptions.ClearCredentialException
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.CreateCredentialInterruptedException
import androidx.credentials.exceptions.CreateCredentialNoCreateOptionException
import androidx.credentials.exceptions.CreateCredentialProviderConfigurationException
import androidx.credentials.exceptions.CreateCredentialUnsupportedException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.GetCredentialInterruptedException
import androidx.credentials.exceptions.GetCredentialProviderConfigurationException
import androidx.credentials.exceptions.GetCredentialUnsupportedException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Scope
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.android.libraries.identity.googleid.GoogleIdTokenParsingException
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.Executor

/**
 * Google Sign-In, Google authorization (scopes) and saved passwords through
 * Android's Credential Manager.
 *
 * Every sheet needs the current Activity, because the system shows it on top
 * of it. A cancelled sheet is a normal result (null / "declined"), every other
 * failure becomes a FlutterError whose code is one of [ErrorCode] and whose
 * details carry Android's exception type and status code.
 */
class AndroidSignInKitPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {

    /** The names of `CredentialErrorCode` on the Dart side. */
    private object ErrorCode {
        const val NO_CREDENTIAL = "noCredential"
        const val INTERRUPTED = "interrupted"
        const val MISCONFIGURED = "misconfigured"
        const val PROVIDER_UNAVAILABLE = "providerUnavailable"
        const val UNSUPPORTED = "unsupported"
        const val NO_PROVIDER = "noProvider"
        const val NO_ACTIVITY = "noActivity"
        const val NETWORK = "network"
        const val INVALID_TOKEN = "invalidToken"
        const val UNEXPECTED_CREDENTIAL = "unexpectedCredential"
        const val BUSY = "busy"
        const val UNKNOWN = "unknown"
    }

    private companion object {
        const val REQUEST_AUTHORIZE = 0x4D41

        /** Written by the google-services Gradle plugin from google-services.json. */
        const val FIREBASE_WEB_CLIENT_ID = "default_web_client_id"
    }

    /** The options of the Google sheet; `initialize` prepares this one. */
    private data class GoogleSheet(
        val serverClientId: String,
        val autoSelect: Boolean,
        val onlyPreviousAccounts: Boolean,
    )

    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var knownPasswords: KnownPasswords
    private var activityBinding: ActivityPluginBinding? = null
    private val activity: Activity? get() = activityBinding?.activity

    private val mainExecutor = Executor(Handler(Looper.getMainLooper())::post)

    // Sheets prepared ahead of time by `initialize` (Android 14+), so they open
    // without the usual wait. A handle works once, so the next one is prepared
    // as soon as it's used.
    private var initialized = false
    private var googleSheet: GoogleSheet? = null
    private var preparedGoogle: PendingGetCredentialHandle? = null
    private var preparedPassword: PendingGetCredentialHandle? = null

    /** The `authorize` call waiting for the user to answer Google's consent screen. */
    private var pendingAuthorization: MethodChannel.Result? = null

    // region FlutterPlugin

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        knownPasswords = KnownPasswords(context)
        channel = MethodChannel(binding.binaryMessenger, "android_sign_in_kit")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    // endregion

    // region ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    // endregion

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "initialize") {
            // Needs no activity, so it can run before the first frame.
            initialize(call)
            result.success(null)
            return
        }
        val activity = activity
        if (activity == null) {
            result.error(ErrorCode.NO_ACTIVITY, "There is no foreground activity to show the sheet on.", null)
            return
        }
        val manager = CredentialManager.create(activity)
        when (call.method) {
            "signInWithGoogle" -> signInWithGoogle(activity, manager, call, result)
            "authorize" -> authorize(activity, call, result)
            "savePassword" -> savePassword(activity, manager, call, result)
            "getPassword" -> getPassword(activity, manager, result)
            "signOut" -> signOut(manager, result)
            else -> result.notImplemented()
        }
    }

    // region Web client ID

    /**
     * The Web client ID passed in, or else the one from google-services.json
     * (the google-services Gradle plugin turns it into a string resource).
     */
    private fun webClientId(call: MethodCall): String? =
        call.argument<String>("serverClientId") ?: firebaseWebClientId()

    private fun firebaseWebClientId(): String? {
        val id = context.resources.getIdentifier(FIREBASE_WEB_CLIENT_ID, "string", context.packageName)
        return if (id == 0) null else context.getString(id).ifBlank { null }
    }

    private fun missingWebClientId(result: MethodChannel.Result) = result.error(
        ErrorCode.MISCONFIGURED,
        "No Web client ID. Pass serverClientId, or add google-services.json with the " +
            "com.google.gms.google-services Gradle plugin.",
        null,
    )

    // endregion

    // region Google Sign-In

    private fun initialize(call: MethodCall) {
        initialized = true
        googleSheet = webClientId(call)?.let { googleSheetOf(it, call) }
        preparedGoogle = null
        preparedPassword = null
        prepareGoogle()
        preparePassword()
    }

    private fun googleSheetOf(serverClientId: String, call: MethodCall) = GoogleSheet(
        serverClientId,
        call.argument<Boolean>("autoSelect") == true,
        call.argument<Boolean>("onlyPreviousAccounts") == true,
    )

    private fun signInWithGoogle(
        activity: Activity,
        manager: CredentialManager,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val serverClientId = webClientId(call) ?: return missingWebClientId(result)
        val nonce = call.argument<String>("nonce")
        val sheet = googleSheetOf(serverClientId, call)
        val option: CredentialOption
        var prepared: PendingGetCredentialHandle? = null
        if (call.argument<Boolean>("useButtonFlow") == true) {
            // The full-screen "Sign in with Google" flow, for a sign-in button.
            option = GetSignInWithGoogleOption.Builder(serverClientId)
                .apply {
                    if (nonce != null) setNonce(nonce)
                    call.argument<String>("hostedDomain")?.let(::setHostedDomainFilter)
                }
                .build()
        } else {
            option = googleSheetOption(sheet, nonce)
            // The prepared sheet only fits the same options, and no nonce
            // (a nonce is different for every request).
            if (nonce == null && sheet == googleSheet) {
                prepared = preparedGoogle
                preparedGoogle = null
            }
        }
        getCredential(activity, manager, option, prepared, ::prepareGoogle, result) { credential ->
            if (credential is CustomCredential &&
                credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL
            ) {
                try {
                    val google = GoogleIdTokenCredential.createFrom(credential.data)
                    result.success(
                        mapOf(
                            "email" to google.id,
                            "idToken" to google.idToken,
                            "displayName" to google.displayName,
                            "givenName" to google.givenName,
                            "familyName" to google.familyName,
                            "photoUrl" to google.profilePictureUri?.toString(),
                            "phoneNumber" to google.phoneNumber,
                        ),
                    )
                } catch (e: GoogleIdTokenParsingException) {
                    result.error(ErrorCode.INVALID_TOKEN, e.message, details(e::class.java.name))
                }
            } else {
                result.error(
                    ErrorCode.UNEXPECTED_CREDENTIAL,
                    "Expected a Google ID token, got ${credential.type}.",
                    details(credential.type),
                )
            }
        }
    }

    private fun googleSheetOption(sheet: GoogleSheet, nonce: String?): GetGoogleIdOption =
        // The bottom sheet listing the Google accounts on the device.
        GetGoogleIdOption.Builder()
            .setServerClientId(sheet.serverClientId)
            .setFilterByAuthorizedAccounts(sheet.onlyPreviousAccounts)
            .setAutoSelectEnabled(sheet.autoSelect)
            .apply { if (nonce != null) setNonce(nonce) }
            .build()

    private fun prepareGoogle() {
        val sheet = googleSheet ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        prepare(googleSheetOption(sheet, null)) { preparedGoogle = it }
    }

    // endregion

    // region Authorization (scopes)

    /**
     * Asks for OAuth scopes with Google's Authorization API. Credential
     * Manager only signs in (an ID token); access to Google APIs needs this.
     * When the scopes were granted before, it answers without any UI.
     */
    private fun authorize(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        if (pendingAuthorization != null) {
            result.error(ErrorCode.BUSY, "Another authorization is waiting for the user.", null)
            return
        }
        val builder = AuthorizationRequest.builder()
            .setRequestedScopes(call.argument<List<String>>("scopes")!!.map(::Scope))
        call.argument<String>("accountEmail")?.let { builder.setAccount(Account(it, "com.google")) }
        call.argument<String>("hostedDomain")?.let(builder::filterByHostedDomain)
        if (call.argument<Boolean>("offlineAccess") == true) {
            val serverClientId = webClientId(call) ?: return missingWebClientId(result)
            builder.requestOfflineAccess(serverClientId, call.argument<Boolean>("forceRefreshToken") == true)
        }
        Identity.getAuthorizationClient(activity).authorize(builder.build())
            .addOnSuccessListener { authorization ->
                val consent = authorization.pendingIntent
                if (!authorization.hasResolution() || consent == null) {
                    result.success(authorizationMap(authorization))
                    return@addOnSuccessListener
                }
                // Not granted yet: show Google's consent screen.
                try {
                    pendingAuthorization = result
                    activity.startIntentSenderForResult(consent.intentSender, REQUEST_AUTHORIZE, null, 0, 0, 0)
                } catch (e: IntentSender.SendIntentException) {
                    pendingAuthorization = null
                    result.error(ErrorCode.UNKNOWN, e.message, details(e::class.java.name))
                }
            }
            .addOnFailureListener { e -> authorizationFailed(result, e) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_AUTHORIZE) return false
        val result = pendingAuthorization ?: return true
        pendingAuthorization = null
        try {
            val authorization = Identity.getAuthorizationClient(context).getAuthorizationResultFromIntent(data)
            result.success(authorizationMap(authorization))
        } catch (e: ApiException) {
            if (resultCode == Activity.RESULT_CANCELED || e.statusCode == CommonStatusCodes.CANCELED) {
                result.success(null) // the user closed or declined the consent screen
            } else {
                authorizationFailed(result, e)
            }
        }
        return true
    }

    @Suppress("DEPRECATION") // toGoogleSignInAccount is the only way to learn the account
    private fun authorizationMap(authorization: AuthorizationResult) = mapOf(
        "accessToken" to authorization.accessToken,
        "grantedScopes" to authorization.grantedScopes,
        "serverAuthCode" to authorization.serverAuthCode,
        "email" to authorization.toGoogleSignInAccount()?.email,
    )

    private fun authorizationFailed(result: MethodChannel.Result, e: Exception) {
        val status = (e as? ApiException)?.statusCode
        val code = when (status) {
            CommonStatusCodes.NETWORK_ERROR -> ErrorCode.NETWORK
            CommonStatusCodes.DEVELOPER_ERROR -> ErrorCode.MISCONFIGURED
            CommonStatusCodes.SIGN_IN_REQUIRED -> ErrorCode.NO_CREDENTIAL
            CommonStatusCodes.INTERRUPTED -> ErrorCode.INTERRUPTED
            CommonStatusCodes.API_NOT_CONNECTED, CommonStatusCodes.SERVICE_DISABLED ->
                ErrorCode.PROVIDER_UNAVAILABLE
            else -> ErrorCode.UNKNOWN
        }
        val type = if (status != null) CommonStatusCodes.getStatusCodeString(status) else e::class.java.name
        result.error(code, e.message, details(type, status))
    }

    // endregion

    // region Passwords

    private fun getPassword(
        activity: Activity,
        manager: CredentialManager,
        result: MethodChannel.Result,
    ) {
        val prepared = preparedPassword
        preparedPassword = null
        // Nothing saved any more: forget what we knew, so savePassword asks again.
        val onNone = { knownPasswords.clear() }
        getCredential(activity, manager, GetPasswordOption(), prepared, ::preparePassword, result, onNone) { credential ->
            if (credential is PasswordCredential) {
                knownPasswords.add(credential.id, credential.password)
                result.success(mapOf("username" to credential.id, "password" to credential.password))
            } else {
                result.error(
                    ErrorCode.UNEXPECTED_CREDENTIAL,
                    "Expected a password, got ${credential.type}.",
                    details(credential.type),
                )
            }
        }
    }

    private fun preparePassword() {
        if (!initialized || Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        prepare(GetPasswordOption()) { preparedPassword = it }
    }

    private fun savePassword(
        activity: Activity,
        manager: CredentialManager,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val username = call.argument<String>("username")!!
        val password = call.argument<String>("password")!!
        if (knownPasswords.contains(username, password)) {
            // Already in the password manager: the sheet would only nag.
            result.success("unchanged")
            return
        }
        manager.createCredentialAsync(
            activity,
            CreatePasswordRequest(username, password),
            null,
            mainExecutor,
            object : CredentialManagerCallback<CreateCredentialResponse, CreateCredentialException> {
                override fun onResult(response: CreateCredentialResponse) {
                    knownPasswords.add(username, password)
                    // The prepared password sheet doesn't list the new one yet.
                    preparedPassword = null
                    preparePassword()
                    result.success("saved")
                }

                override fun onError(e: CreateCredentialException) {
                    val code = when (e) {
                        is CreateCredentialCancellationException -> return result.success("declined")
                        is CreateCredentialNoCreateOptionException -> ErrorCode.NO_PROVIDER
                        is CreateCredentialInterruptedException -> ErrorCode.INTERRUPTED
                        is CreateCredentialProviderConfigurationException -> ErrorCode.PROVIDER_UNAVAILABLE
                        is CreateCredentialUnsupportedException -> ErrorCode.UNSUPPORTED
                        else -> ErrorCode.UNKNOWN
                    }
                    result.error(code, e.errorMessage?.toString() ?: e.message, details(e.type))
                }
            },
        )
    }

    // endregion

    // region Shared

    /**
     * Shows the sheet for [option], straight from the [prepared] handle when
     * there is one, then prepares the next sheet with [prepareNext]. A
     * cancelled sheet completes with null.
     */
    private fun getCredential(
        activity: Activity,
        manager: CredentialManager,
        option: CredentialOption,
        prepared: PendingGetCredentialHandle?,
        prepareNext: () -> Unit,
        result: MethodChannel.Result,
        onNoCredential: () -> Unit = {},
        onCredential: (Credential) -> Unit,
    ) {
        val callback = object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
            override fun onResult(response: GetCredentialResponse) {
                prepareNext()
                onCredential(response.credential)
            }

            override fun onError(e: GetCredentialException) {
                prepareNext()
                val message = e.errorMessage?.toString() ?: e.message
                val code = when (e) {
                    is GetCredentialCancellationException -> return result.success(null)
                    is NoCredentialException -> {
                        onNoCredential()
                        ErrorCode.NO_CREDENTIAL
                    }
                    is GetCredentialInterruptedException -> ErrorCode.INTERRUPTED
                    is GetCredentialProviderConfigurationException -> ErrorCode.PROVIDER_UNAVAILABLE
                    is GetCredentialUnsupportedException -> ErrorCode.UNSUPPORTED
                    else -> googleErrorCode(message)
                }
                result.error(code, message, details(e.type))
            }
        }
        if (prepared != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            manager.getCredentialAsync(activity, prepared, null, mainExecutor, callback)
        } else {
            val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
            manager.getCredentialAsync(activity, request, null, mainExecutor, callback)
        }
    }

    /**
     * Lets Credential Manager look up the credentials for [option] now, so
     * showing the sheet later is instant. Older Android versions have no such
     * API; there the sheet is built when it's shown.
     */
    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun prepare(option: CredentialOption, onPrepared: (PendingGetCredentialHandle?) -> Unit) {
        CredentialManager.create(context).prepareGetCredentialAsync(
            GetCredentialRequest.Builder().addCredentialOption(option).build(),
            null,
            mainExecutor,
            object : CredentialManagerCallback<PrepareGetCredentialResponse, GetCredentialException> {
                override fun onResult(response: PrepareGetCredentialResponse) =
                    onPrepared(response.pendingGetCredentialHandle)

                // Not fatal: the sheet is then built when it's shown.
                override fun onError(e: GetCredentialException) = onPrepared(null)
            },
        )
    }

    private fun signOut(manager: CredentialManager, result: MethodChannel.Result) {
        manager.clearCredentialStateAsync(
            ClearCredentialStateRequest(),
            null,
            mainExecutor,
            object : CredentialManagerCallback<Void?, ClearCredentialException> {
                override fun onResult(response: Void?) {
                    // A prepared auto-select sheet would still sign the old account in.
                    preparedGoogle = null
                    prepareGoogle()
                    result.success(null)
                }

                override fun onError(e: ClearCredentialException) =
                    result.error(ErrorCode.UNKNOWN, e.errorMessage?.toString() ?: e.message, details(e.type))
            },
        )
    }

    /** Android's exception type (and Play services status code) for the Dart exception. */
    private fun details(type: String, statusCode: Int? = null) =
        mapOf("type" to type, "statusCode" to statusCode)

    /**
     * Play services reports a wrong client ID or a missing SHA-1 only through
     * its message, e.g. "[28444] Developer console is not set up correctly."
     */
    private fun googleErrorCode(message: String?): String = when {
        message == null -> ErrorCode.UNKNOWN
        "28444" in message || "Developer console" in message -> ErrorCode.MISCONFIGURED
        "network" in message.lowercase() -> ErrorCode.NETWORK
        else -> ErrorCode.UNKNOWN
    }

    // endregion
}
