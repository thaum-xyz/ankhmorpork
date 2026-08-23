# PowerWalker VFI 1500 LICR IoT — Modbus TCP register map

`192.168.1.141:502`, function code 3, unit id ignored (1, 2, 3 and 255 all
answer identically). Reads only — do not write, these are live UPS settings.

PowerWalker does not publish the map; the manual says to "contact your service
for protocol details". Everything below was derived by reading registers while
comparing against the front-panel LCD, so each entry is confirmed against a
displayed value rather than inferred.

## Identity (static, ASCII, big-endian per register)

| Registers | Value |
|-----------|-------|
| 0–4   | `PHOENIXTEC` (Eaton subsidiary; OEM behind PowerWalker) |
| 16–24 | `VFI 1500 LICR IoT` |
| 48–53 | `00.03.1760` — UPS firmware |
| 56–63 | `CPANR1398610001` — serial |
| 286–290 | `01.08.000` — network stack version |
| 296–299 | `4aebc90e` — device id |

## Telemetry

| Reg | Metric | Scale | Verified against LCD |
|-----|--------|-------|----------------------|
| 128 | temperature      | ÷10 °C | 25.2–25.4 vs 25.4 °C |
| 129 | input frequency  | ÷10 Hz | 50.0 Hz |
| 132 | input voltage    | ÷10 V  | 232.7 vs 232 V |
| 144 | output frequency | ÷10 Hz | 50.0 Hz |
| 147 | output voltage   | ÷10 V  | 230.3 vs 230 V |
| 153 | output current   | ÷10 A  | 1.1–1.4 vs 1.1–1.3 A |
| 162 | load             | %      | 17–21 vs 17–21 % |
| 165 | runtime left     | min    | 57–78 vs 66–79 min |
| 169 | battery charge   | %      | 100 % |
| 170 | battery voltage  | ÷10 V  | 52.7 V (48 V string, charging) |
| 176 | bypass voltage   | ÷10 V  | tracks input |
| 250 | nominal output V | ÷10 V  | 230.0 V |

`0xFFFF` means "not applicable" — the three-phase registers read that way on
this single-phase unit.

Apparent power is not exposed; derive it as `(147/10) * (153/10)`, which gives
~287 VA against the 280–300 VA the panel showed. Real power would additionally
need the power factor, which is also absent.

Still unidentified: 153's neighbours 156 (1–2) and 159 (2–3), and 166, which
swings 0–45 with no obvious correlation.

## Enabling it

Modbus TCP is **off by default**. Enable it from the front panel; until then
port 502 accepts the TCP connection but returns zero bytes, which looks exactly
like a hung service. The "IoT" (cloud) feature is separate and can stay off.

SNMP is not listening — no reply to v2c `public` on udp/161. The intelligent
card slot is empty; this is the UPS's built-in Ethernet port, so there is no
NMC to reset.
