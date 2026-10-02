package dev.parth.android_sign_in_kit

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.GeneralSecurityException
import java.security.Key
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.Mac

/**
 * Remembers which usernames and passwords are already in the user's password
 * manager, so `savePassword` doesn't ask to save them again. Google Password
 * Manager shows its "Save password?" sheet even for a password it already has,
 * and apps can't read what's saved without showing a sheet.
 *
 * Only an HMAC of each pair is stored, keyed with a key that never leaves the
 * Android Keystore, so the stored values can't be used to guess a password.
 */
internal class KnownPasswords(context: Context) {

    private companion object {
        const val PREFS = "android_sign_in_kit"
        const val KEY = "known_passwords"
        const val KEY_ALIAS = "android_sign_in_kit.known_passwords"
        const val MAX = 20
    }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun contains(username: String, password: String): Boolean {
        val digest = digest(username, password) ?: return false
        return digest in load()
    }

    fun add(username: String, password: String) {
        val digest = digest(username, password) ?: return
        val known = load().filter { it != digest } + digest
        prefs.edit().putString(KEY, known.takeLast(MAX).joinToString(",")).apply()
    }

    /** Nothing is saved for this app any more (e.g. the user deleted it). */
    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    private fun load(): List<String> =
        prefs.getString(KEY, null)?.split(',')?.filter { it.isNotEmpty() } ?: emptyList()

    /** Null when the Keystore fails; the password is then treated as new. */
    private fun digest(username: String, password: String): String? = try {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(key())
        mac.update(username.toByteArray())
        mac.update(0.toByte())
        mac.update(password.toByteArray())
        Base64.encodeToString(mac.doFinal(), Base64.NO_WRAP or Base64.NO_PADDING)
    } catch (e: GeneralSecurityException) {
        null
    }

    private fun key(): Key {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        keyStore.getKey(KEY_ALIAS, null)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_SIGN).build())
        return generator.generateKey()
    }
}
