package com.example.swifty_protein

import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.content.Intent
import android.net.Uri
import java.io.File
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec

class MainActivity : FlutterActivity() {
    private val prefs by lazy { getSharedPreferences("secure_accounts", MODE_PRIVATE) }
    private val alias = "swifty_protein_accounts"
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "swifty_protein/share").setMethodCallHandler { call, result ->
            if (call.method != "share") { result.notImplemented(); return@setMethodCallHandler }
            try {
                val png = call.argument<ByteArray>("png") ?: throw IllegalArgumentException("Missing image")
                if (png.size > 10000000) throw IllegalArgumentException("Image too large")
                File(cacheDir, "molecule.png").writeBytes(png)
                val uri = Uri.parse("content://$packageName.share/molecule.png")
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "image/png"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(intent, "Share molecule"))
                result.success(null)
            } catch (e: Exception) { result.error("share_failed", e.message, null) }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "swifty_protein/auth").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "hasAccount" -> result.success(accounts().length() > 0)
                    "register" -> {
                        val name = (call.argument<String>("username") ?: "").trim().lowercase()
                        val password = call.argument<String>("password") ?: ""
                        if (!name.matches(Regex("[a-z0-9_]{3,32}")) || password.length < 12)
                            result.error("invalid", "Username: 3–32 letters, digits or underscores. Password: at least 12 characters.", null)
                        else {
                            val data = accounts()
                            if (data.has(name)) result.error("exists", "Username already exists.", null)
                            else {
                                data.put(name, passwordRecord(password))
                                save(data)
                                prefs.edit().putString("last_user", name).apply()
                                result.success(true)
                            }
                        }
                    }
                    "login" -> {
                        val name = (call.argument<String>("username") ?: "").trim().lowercase()
                        val password = call.argument<String>("password") ?: ""
                        val record = accounts().optJSONObject(name)
                        if (record != null && verify(password, record)) {
                            prefs.edit().putString("last_user", name).apply()
                            result.success(true)
                        } else result.error("invalid_credentials", "Incorrect username or password.", null)
                    }
                    "biometricAvailable" -> result.success(biometricAvailable())
                    "biometricLogin" -> biometricLogin(result)
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("auth_error", e.message ?: "Authentication failed.", null) }
        }
    }
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        return generator.generateKey()
    }
    private fun accounts(): JSONObject {
        val encoded = prefs.getString("accounts", null) ?: return JSONObject()
        val bytes = Base64.decode(encoded, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        return JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
    }
    private fun save(data: JSONObject) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.iv + cipher.doFinal(data.toString().toByteArray(Charsets.UTF_8))
        prefs.edit().putString("accounts", Base64.encodeToString(encrypted, Base64.NO_WRAP)).apply()
    }
    private fun derive(password: String, salt: ByteArray): ByteArray {
        val spec = PBEKeySpec(password.toCharArray(), salt, 120000, 256)
        return try { SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded }
        finally { spec.clearPassword() }
    }
    private fun passwordRecord(password: String): JSONObject {
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        return JSONObject().put("salt", Base64.encodeToString(salt, Base64.NO_WRAP))
            .put("hash", Base64.encodeToString(derive(password, salt), Base64.NO_WRAP))
    }
    private fun verify(password: String, record: JSONObject): Boolean {
        val salt = Base64.decode(record.getString("salt"), Base64.NO_WRAP)
        val hash = Base64.decode(record.getString("hash"), Base64.NO_WRAP)
        return MessageDigest.isEqual(hash, derive(password, salt))
    }
    private fun biometricAvailable(): Boolean {
        if (Build.VERSION.SDK_INT < 29 || prefs.getString("last_user", null) == null) return false
        return getSystemService(BiometricManager::class.java).canAuthenticate() == BiometricManager.BIOMETRIC_SUCCESS
    }
    private fun biometricLogin(result: MethodChannel.Result) {
        if (!biometricAvailable()) { result.error("unavailable", "Biometric authentication is unavailable.", null); return }
        if (Build.VERSION.SDK_INT >= 29) {
            val completed = AtomicBoolean(false)
            BiometricPrompt.Builder(this).setTitle("Unlock Swifty Protein")
                .setSubtitle("Confirm your identity")
                .setNegativeButton("Cancel", mainExecutor) { _, _ -> if (completed.compareAndSet(false, true)) result.error("cancelled", "Authentication cancelled.", null) }
                .build().authenticate(CancellationSignal(), mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) { if (completed.compareAndSet(false, true)) result.success(true) }
                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) { if (completed.compareAndSet(false, true)) result.error("biometric_failed", errString.toString(), null) }
                })
        }
    }
}
