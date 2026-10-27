package dev.phonecheck

import org.junit.Assert.*
import org.junit.Test

class NotificationCommandTest {
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
