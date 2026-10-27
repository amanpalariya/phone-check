package dev.phonecheck

import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

internal enum class DemoScenario(val number: Int, val label: String, val detail: String) {
    BASIC(101, "Basic", "Title, text, and tap target"),
    LONG_TEXT(102, "Expanded text", "Long content and Unicode"),
    INBOX(103, "Inbox", "Three separate lines"),
    CHAT(104, "Chat & reply", "Conversation, senders, and inline reply"),
    PICTURE(105, "Picture", "A bounded image preview"),
    PROGRESS(106, "Progress", "Determinate download updates"),
    INDETERMINATE(107, "Indeterminate", "An ongoing operation"),
    GROUP(108, "Grouped", "Two children and a group summary"),
    ONGOING(109, "Non-dismissible", "Ongoing notification"),
    ACTIONS(110, "Action buttons", "Archive and mark read"),
    MEDIA(111, "Media", "Play, pause, and next"),
    CALL(112, "Incoming call", "Synthetic answer and decline actions"),
    SILENT(113, "Silent", "No phone alert sound"),
    PRIVATE(114, "Private", "Public lock-screen version"),
    CUSTOM(115, "Custom layout", "Readable text fallback"),
    EXPIRED(116, "Expired action", "A canceled PendingIntent"),
    PROTECTED(117, "Protected action", "Phone must be unlocked"),
    CHOICES(118, "Suggested replies", "Fixed response choices"),
    ATTACHMENT_INPUT(119, "Attachment action", "Requires input on the phone"),
    MULTIPLE_INPUTS(120, "Multiple inputs", "Requires input on the phone")
}

internal object TestbedState {
    var lastReceipt by mutableStateOf("No actions yet")
    var lastOperation by mutableStateOf("")
    var receiptCount by mutableStateOf(0)
    var progress by mutableStateOf(25)
    val operations = mutableStateMapOf<String, Int>()
    var lastReply: String? = null // Synthetic test input only; never persisted or logged.
    fun record(operation: String, reply: String? = null) {
        operations[operation] = (operations[operation] ?: 0) + 1
        lastOperation = operation
        if (reply != null) lastReply = reply
        receiptCount++
        lastReceipt = when (operation) {
            "reply" -> "Reply received"
            "open" -> "Tap received"
            "removed" -> "Notification removed"
            else -> operation.replaceFirstChar { it.uppercase() } + " received"
        }
    }
}
