# Hardware support — DevOS 1.0 (target laptop)

Reference machine: **Infinix laptop, Intel Core i3-1215U (Alder Lake-U), Intel UHD Graphics**.
Yeh document batata hai ki us laptop ka har component DevOS image me kaise chalega,
aur kya cheez verify ki gayi hai.

Image ke andar poore non-free firmware metapackages already installed hain
(`firmware-linux-nonfree 20250410-2`, `firmware-sof-signed 2025.01-1`,
`intel-microcode 3.20251111.1`), isliye laptop se alag se kuch copy karne ki
zaroorat nahi padi — 851 MB `/lib/firmware` image me hai.

## Component → driver → firmware

| Component (lspci/lsusb) | Kernel driver | Firmware / module | Status |
|---|---|---|---|
| Wi-Fi: Intel Alder Lake-P CNVi `8086:51f0` (AX201) | `iwlwifi` + `iwlmvm` | `iwlwifi-so-a0-gf-a0-89.ucode`, `-72`, `.pnvm` | ✅ image me |
| Bluetooth: Intel AX201 `8087:0026` | `btusb` | `intel/ibt-0040-0041.sfi` + `.ddc` | ✅ image me |
| Audio: Intel ADL-P HDA `8086:51c8` (Realtek ALC269) | `snd_sof_pci_intel_tgl`, `snd_hda_intel`, `snd_hda_codec_alc269` | `intel/sof/sof-adl.ri` + `intel/sof-tplg/*` (SOF topology) | ✅ image me |
| GPU: Intel UHD `8086:46b3` | `i915` | `i915/adlp_guc_70.bin`, `i915/tgl_huc.bin`, `i915/adlp_dmc.bin` | ✅ image me |
| Touchpad (I2C HID) | `i2c_hid_acpi`, `hid_multitouch` | koi firmware nahi | ✅ module image me |
| Camera: Microdia USB `0c45:636b` | `uvcvideo` | koi firmware nahi | ✅ module image me |
| NVMe: Longsys/FORESEE `1d97:5216` | `nvme` | built-in | ✅ |
| Thermal / power | `thermald`, `intel_pstate` | — | ✅ installed |
| Wi-Fi regulatory DB (5 GHz) | — | `wireless-regdb` | ✅ installed |
| CPU microcode | — | `intel-microcode` (12th gen included) | ✅ installed |

Kernel: `6.12.117+deb13-amd64` (Debian 13 trixie). Alder Lake support is mature
in this branch.

## Verify on the actual machine

Live ISO boot karke terminal me:

```bash
lspci -k | grep -A2 -E "Network|Audio|VGA"   # driver in use?
dmesg | grep -iE "firmware|iwlwifi|sof|i915"  # firmware load errors?
ip link                                        # wlan0 exists?
aplay -l                                       # sound card?
libinput list-devices | grep -i touchpad       # touchpad?
devos-audio diagnose                           # sab kuch ek report me
```

Sound ke liye `devos-audio` hi kaafi hai — cards, kernel modules, firmware,
UCM profiles, dmesg aur PipeWire nodes sab ek report me
(`/tmp/devos-audio-report.txt`) aa jaate hain. `devos-audio test` se ek test tone
bajti hai aur `devos-audio fix` safe repairs karta hai (unmute, audio group,
PipeWire/WirePlumber restart). App grid me **DevOS Audio** launcher bhi hai.

Agar koi line `firmware: failed to load` dikhaye, us file ka naam note karke
`/lib/firmware` me daalna hai (host Ubuntu se copy kar sakte hain) aur
`update-initramfs -u` chala kar ISO rebuild karna hai.

## Kya abhi verified nahi hai

- Yeh sab VM me verify **nahi** ho sakta (VM ka virtual hardware alag hai).
  Live USB par asli laptop par ek baar check karna baaki hai.
- Secure Boot: image signed shim ke bina hai; BIOS me Secure Boot off karna padega
  (ya MOK enroll karna hoga).
