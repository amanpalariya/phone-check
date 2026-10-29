package dev.phonecheck

import android.app.Activity
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.GoogleAuthProvider
import com.google.firebase.database.FirebaseDatabase
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Google establishes ownership; QR pairing separately establishes the encryption secret. */
internal object CloudAccount {
    val auth: FirebaseAuth get() = FirebaseAuth.getInstance()
    val database: FirebaseDatabase by lazy {
        FirebaseDatabase.getInstance().apply { setPersistenceEnabled(false) }
    }
    suspend fun signIn(activity: Activity) {
        val clientID = activity.getString(R.string.default_web_client_id)
        val result = CredentialManager.create(activity).getCredential(activity,
            GetCredentialRequest.Builder().addCredentialOption(
                GetSignInWithGoogleOption.Builder(clientID).build()).build())
        val google = GoogleIdTokenCredential.createFrom(result.credential.data)
        suspendCancellableCoroutine<Unit> { continuation ->
            auth.signInWithCredential(GoogleAuthProvider.getCredential(google.idToken, null))
                .addOnSuccessListener { if (continuation.isActive) continuation.resume(Unit) }
                .addOnFailureListener { if (continuation.isActive) continuation.resumeWithException(it) }
        }
    }
    fun root(uid: String) = database.getReference("accounts").child(uid)
}
