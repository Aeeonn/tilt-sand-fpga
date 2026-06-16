"""Golden model for uart_tx (8N1, LSB-first). See docs/SPEC_uart_tx.md."""


def expected_frame(byte: int) -> list[int]:
    """Expected 10-bit serial frame for one transmitted byte:
    [start(0), d0..d7 (LSB first), stop(1)]."""
    bits = [0]
    for i in range(8):
        bits.append((byte >> i) & 1)
    bits.append(1)
    return bits


if __name__ == "__main__":
    for b in (0x00, 0xFF, 0xA5, 0x3C, 0x01, 0x80):
        print(f"{b:#04x}: {expected_frame(b)}")
