package dev.phonecheck

import com.google.firebase.database.*

/** Claim an unexpired invite atomically. Only the HMAC proof goes to the database. */
internal object CloudPairing {
    fun join(pairing: Pairing, completion: (Boolean) -> Unit) {
        val uid = CloudAccount.auth.currentUser?.uid
        if (uid == null || uid != pairing.ownerUID || pairing.pairID == null) { completion(false); return }
        val pairRef = CloudAccount.root(uid).child("control/pair")
        // Transactions first run against the local cache, which is empty on a new phone.
        pairRef.get().addOnSuccessListener {
            pairRef.runTransaction(object : Transaction.Handler {
                override fun doTransaction(current: MutableData): Transaction.Result {
                    if (current.child("id").getValue(String::class.java) != pairing.pairID ||
                        (current.child("expiresAt").getValue(Long::class.java) ?: 0) <= System.currentTimeMillis() ||
                        current.child("phone").value != null) return Transaction.abort()
                    current.child("phone").value = pairing.peer
                    current.child("proof").value = Wire.b64(Wire.derive(pairing.secret, "cloud-pair", pairing.peer.toByteArray()))
                    return Transaction.success(current)
                }
                override fun onComplete(failure: DatabaseError?, committed: Boolean, value: DataSnapshot?) {
                    completion(failure == null && committed && CloudAccount.auth.currentUser?.uid == uid)
                }
            }, false)
        }.addOnFailureListener { completion(false) }
    }
}
