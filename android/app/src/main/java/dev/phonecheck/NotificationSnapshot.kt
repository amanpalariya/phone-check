package dev.phonecheck

import org.json.JSONArray
import org.json.JSONObject

internal object NotificationSnapshot {
    /** One transport job writes the entire snapshot before any live updates. */
    fun frames(notices: Collection<JSONObject>): List<JSONObject> {
        val frames = mutableListOf(JSONObject().put("type", "snapshot_begin"))
        var chunk = mutableListOf<JSONObject>()
        var bytes = 0
        for (notice in notices) {
            val size = notice.toString().toByteArray().size
            if (chunk.isNotEmpty() && bytes + size > 400000) {
                frames += JSONObject().put("type", "snapshot_items").put("items", JSONArray(chunk))
                chunk = mutableListOf(); bytes = 0
            }
            chunk += notice; bytes += size
        }
        if (chunk.isNotEmpty()) frames += JSONObject().put("type", "snapshot_items").put("items", JSONArray(chunk))
        frames += JSONObject().put("type", "snapshot_end")
        return frames
    }
}
