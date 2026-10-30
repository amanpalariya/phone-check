package dev.phonecheck

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject

class NotificationCommandTest {
    private fun message() = JSONObject()
        .put("type", "action").put("command", "id").put("key", "key")
        .put("revision", "a".repeat(64)).put("action", "action")
        .put("sentAt", 100000).put("expiresAt", 108000)

    @Test fun parsesRepliesAndSeekPositionsWithoutChangingCapabilities() {
        val reply = NotificationCommand.parse(message().put("text", "Hello"))!!
        assertEquals("Hello", reply.text)
        assertEquals(CommandKind.ACTION, reply.kind)
        assertNull(reply.position)
        assertTrue(reply.isFresh(100000))
        assertEquals(1234L, NotificationCommand.parse(message().put("position", 1234))!!.position)
        assertEquals(Long.MAX_VALUE, NotificationCommand.parse(message().put("position", Long.MAX_VALUE))!!.position)
        val dismiss = NotificationCommand.parse(message().put("type", "dismiss"))!!
        assertEquals(CommandKind.DISMISS, dismiss.kind)
        assertNull(dismiss.actionId)
    }

    @Test fun rejectsMalformedOrUnboundedCommandsBeforeDispatch() {
        for ((field, value) in listOf(
            "type" to "unknown", "command" to "", "command" to "x".repeat(65),
            "key" to "", "key" to "x".repeat(4097), "revision" to "short",
            "action" to "", "text" to "x".repeat(4001)
        )) assertNull(field, NotificationCommand.parse(message().put(field, value)))
        for (position in listOf(-1, 1.5, "1234", JSONObject.NULL, true, 1e30)) {
            assertNull("Invalid seek position", NotificationCommand.parse(message().put("position", position)))
        }
        assertNotNull(NotificationCommand.parse(message().put("text", "x".repeat(4000))))
    }

    private fun command(id: String = "id", sent: Long = 100000, expires: Long = sent + 8000) =
        NotificationCommand(id, "key", "revision", CommandKind.ACTION, "action", "Sample", sent, expires)
    @Test fun rejectsExpiredFutureAndExcessiveLifetime() {
        assertTrue(command().isFresh(100000))
        assertFalse(command().isFresh(108001))
        assertFalse(command(sent = 110000).isFresh(100000))
        assertFalse(command(expires = 120000).isFresh(100000))
        assertFalse(command(expires = 100000).isFresh(100000))
        assertFalse(command(sent = Long.MIN_VALUE).isFresh(100000))
    }
    @Test fun duplicateCommandsReturnReceiptWithoutRepeatingSideEffects() {
        val ledger = CommandLedger()
        val command = command()
        assertEquals(CommandLedger.Admission.New, ledger.accept(command, 0))
        assertEquals(CommandLedger.Admission.Repeated(null), ledger.accept(command, 1))
        ledger.complete(command.id, "sent")
        assertEquals(CommandLedger.Admission.Repeated("sent"), ledger.accept(command, 2))
        assertEquals(CommandLedger.Admission.Rejected, ledger.accept(command.copy(text = "Changed"), 3))
    }
    @Test fun boundsLedgerAndClearsOnlyAfterReplayWindow() {
        val ledger = CommandLedger(capacity = 1)
        assertEquals(CommandLedger.Admission.New, ledger.accept(command(), 0))
        assertEquals(CommandLedger.Admission.Rejected, ledger.accept(command(id = "second"), 1))
        assertEquals(CommandLedger.Admission.New, ledger.accept(command(id = "second"), 30001))
        ledger.clear()
        assertEquals(CommandLedger.Admission.New, ledger.accept(command(), 30002))
    }
}
