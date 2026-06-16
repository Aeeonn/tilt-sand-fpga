"""Golden model for uart_monitor's peek/poke protocol. See docs/SPEC_uart_monitor.md."""

CMD_PEEK = 0x52  # 'R'
CMD_POKE = 0x57  # 'W'


def run(regs: list[int], rx_bytes: list[int]) -> tuple[list[int], list[int]]:
    """Process a stream of received bytes against the protocol FSM.
    Returns (final_regs, tx_bytes): tx_bytes is the list of bytes the
    monitor would transmit, in order."""
    regs = list(regs)
    tx_bytes = []
    i = 0
    while i < len(rx_bytes):
        cmd = rx_bytes[i]
        if cmd == CMD_PEEK:
            addr = rx_bytes[i + 1] & 0xF
            tx_bytes.append(regs[addr])
            i += 2
        elif cmd == CMD_POKE:
            addr = rx_bytes[i + 1] & 0xF
            data = rx_bytes[i + 2]
            regs[addr] = data
            tx_bytes.append(data)
            i += 3
        else:
            i += 1  # unknown command, ignored
    return regs, tx_bytes


if __name__ == "__main__":
    regs0 = [0] * 16
    seq = [CMD_POKE, 0x03, 0xA5, CMD_PEEK, 0x03,
           CMD_POKE, 0x0F, 0x42, 0x99, CMD_PEEK, 0x00]
    regs1, tx = run(regs0, seq)
    print("regs:", [f"{r:#04x}" for r in regs1])
    print("tx  :", [f"{b:#04x}" for b in tx])
