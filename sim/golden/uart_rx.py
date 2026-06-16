"""Golden model for uart_rx (8N1, LSB-first). See docs/SPEC_uart_rx.md."""


def receive_frame(frame: list[int]) -> tuple[int, bool]:
    """Inverse of uart_tx.expected_frame: given a 10-bit frame
    [start, d0..d7, stop], return (byte, framing_error)."""
    assert len(frame) == 10
    byte = 0
    for i in range(8):
        byte |= frame[1 + i] << i
    framing_error = (frame[9] != 1)
    return byte, framing_error


if __name__ == "__main__":
    def _frame(byte):
        bits = [0]
        for i in range(8):
            bits.append((byte >> i) & 1)
        bits.append(1)
        return bits

    for b in (0x00, 0xFF, 0xA5, 0x3C):
        frame = _frame(b)
        print(f"{b:#04x}: frame={frame} -> {receive_frame(frame)}")

    bad = _frame(0x55)
    bad[9] = 0
    print(f"corrupted stop: frame={bad} -> {receive_frame(bad)}")
