#!/usr/bin/env python3
"""
DeskSurfer 브리지 — 로봇(블루투스 시리얼) ↔ 버츄얼 펫(파일) 중계.

이 프로그램은 PC에서 상시 돌아가며, HC-06 블루투스로 연결된 책상 로봇과
Godot 펫 앱을 이어준다. 둘은 서로를 직접 모르고, 오직 이 브리지를 통해서만
하나의 존재처럼 이어진다.

━━ 구현된 것 ━━
  방향 A (로봇 → 펫)  [2단계]
     로봇이 집에 도착하면 블루투스로 "ARRIVED"를 보낸다 → 그걸 받으면
     펫의 command 파일에 "exit_home"을 써서 펫을 볼에서 꺼낸다.

  방향 B (펫 → 로봇)  [3단계]
     펫이 볼에 들어가면 pet.gd 가 state 파일을 "home"으로 바꾼다 → 그 변화를
     감지하면 로봇에 'F'(자유 주행)를 보내 책상 위를 돌아다니게 한다.

  수동 트리거 (키보드)  [4단계]
     'F'로 돌아다니는 로봇을 집으로 부르는 건 사람이 결정한다. 브리지 콘솔에서
     키를 누르면 로봇에 단일 문자 명령을 보낸다:
        h → H(귀가)   f → F(주행)   s → S(정지)   ? → 상태요청   q/Esc → 종료
     (h 를 누르면 로봇이 비콘 유도로 귀가 → 도착 시 ARRIVED → 위 방향 A로
      펫이 볼에서 나오며 한 바퀴가 완성된다.)

━━ 다음 단계에서 추가할 것 ━━
  · 5단계 안정화: 펫이 나올 때(state="virtual") 로봇에 'S'(정지) 자동 전송 등

포트 번호가 매번 바뀌는 문제 → 하드코딩하지 않고 블루투스 시리얼 포트를
자동 탐지한다(발신/Outgoing COM). 원하면 BRIDGE_PORT 환경변수로 강제 지정한다.

실행 전:  pip install pyserial
실행:     python bridge.py       (키 입력을 받으려면 이 콘솔 창에 포커스를 둔다)
"""

import os
import time
from pathlib import Path

import serial
from serial.tools import list_ports

# 키보드 논블로킹 입력(Windows 전용). 다른 OS면 수동 트리거만 비활성화된다.
try:
    import msvcrt
    HAVE_KB = True
except ImportError:
    msvcrt = None
    HAVE_KB = False


# 로봇 펌웨어(main_robot.ino)의 Serial/HC-06 속도와 반드시 일치해야 한다.
BAUD = 9600

# state 파일을 얼마나 자주 확인할지(초). 파일 I/O라 너무 자주 읽지 않는다.
STATE_POLL_SEC = 0.2


# ---------------------------------------------------------------------------
#  브리지 폴더 (펫과 공유하는 "우편함")
# ---------------------------------------------------------------------------
def find_bridge_dir() -> Path:
    """펫(pet.gd)이 쓰는 것과 똑같은 폴더를 찾는다.

    기본값은 ~/.desktop-pet (Windows: %USERPROFILE%\\.desktop-pet).
    펫과 브리지 둘 다 PET_BRIDGE_DIR 환경변수로 같은 폴더를 가리키게 할 수도 있다.
    """
    d = os.environ.get("PET_BRIDGE_DIR", "").strip()
    if not d:
        home = os.environ.get("USERPROFILE") or os.environ.get("HOME") or "."
        d = os.path.join(home, ".desktop-pet")
    p = Path(d)
    p.mkdir(parents=True, exist_ok=True)
    return p


def send_to_pet(bridge_dir: Path, cmd: str) -> None:
    """펫에게 명령을 보낸다 = command 파일에 써넣는다.

    펫은 command 파일을 0.3초마다 읽고 곧바로 삭제하므로, 그냥 덮어쓰면 된다.
    받을 수 있는 명령: enter_home / exit_home / feed / play
    """
    (bridge_dir / "command").write_text(cmd + "\n", encoding="utf-8")
    print(f"  [펫 ←] command = {cmd}")


def read_state(bridge_dir: Path):
    """펫이 쓴 state 파일을 읽는다. "virtual" 또는 "home".

    반환: 정리된 문자열, 파일 없으면 "", 읽기 실패(펫이 쓰는 중 등)면 None.
    None이면 호출부는 이번 틱을 건너뛴다(잘못된 값으로 오동작하지 않도록).
    """
    path = bridge_dir / "state"
    try:
        if not path.exists():
            return ""
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return None


# ---------------------------------------------------------------------------
#  블루투스 시리얼 포트 자동 탐지
# ---------------------------------------------------------------------------
def candidate_ports() -> list:
    """열어볼 후보 COM 포트 목록. BRIDGE_PORT가 있으면 그것만 쓴다.

    Windows에서 HC-06을 페어링하면 발신/수신 두 COM이 'Standard Serial over
    Bluetooth link (COMx)' 같은 이름으로 잡힌다. 설명에 'bluetooth'가 들어간
    포트를 후보로 모으고, main에서 실제로 열리는 것(=발신 COM)을 골라 쓴다.
    """
    forced = os.environ.get("BRIDGE_PORT", "").strip()
    if forced:
        return [forced]
    bt = []
    for p in list_ports.comports():
        blob = f"{p.description} {p.manufacturer or ''} {p.hwid or ''}".lower()
        if "bluetooth" in blob:
            bt.append(p.device)
    return sorted(bt)


def open_serial(port: str) -> serial.Serial:
    ser = serial.Serial(port, BAUD, timeout=0.2)
    time.sleep(0.3)          # HC-06 연결 직후 잠깐 안정화
    ser.reset_input_buffer()
    return ser


def connect():
    """후보 포트를 하나씩 열어보고 처음 성공한 것을 돌려준다. 없으면 None."""
    ports = candidate_ports()
    if not ports:
        print("[대기] 블루투스 시리얼 포트를 못 찾음. "
              "(HC-06 페어링 확인 / BRIDGE_PORT 로 지정 가능)")
        return None
    for cand in ports:
        try:
            ser = open_serial(cand)
            print(f"[연결] {cand} @ {BAUD}bps")
            return ser
        except Exception as e:
            print(f"  {cand} 열기 실패: {e}")
    return None


def send_to_robot(ser: serial.Serial, ch: str, why: str = "") -> None:
    """로봇에 단일 문자 명령을 보낸다. F=주행 S=정지 H=귀가 G=재출발 ?=상태."""
    try:
        ser.write(ch.encode("ascii"))
        ser.flush()
        note = f" ({why})" if why else ""
        print(f"  [로봇 ←] '{ch}'{note}")
    except Exception as e:
        print(f"  [로봇 ←] '{ch}' 전송 실패: {e}")


# ---------------------------------------------------------------------------
#  수동 트리거 (키보드)
# ---------------------------------------------------------------------------
def key_action(ch: str):
    """키 한 글자 → (로봇에 보낼 명령 or None, 종료요청 bool).

    순수 함수라 하드웨어 없이 단위 테스트할 수 있다.
    """
    low = ch.lower()
    if low == "h":
        return ("H", False)     # 귀가 (비콘 유도)
    if low == "f":
        return ("F", False)     # 주행
    if low == "s":
        return ("S", False)     # 정지
    if ch == "?":
        return ("?", False)     # 상태 요청
    if low == "q" or ch == "\x1b":
        return (None, True)     # 종료 (q 또는 Esc)
    return (None, False)


def poll_keyboard(ser: serial.Serial) -> bool:
    """콘솔 키 입력을 논블로킹으로 처리한다. 종료 요청 시 True.

    이 콘솔 창에 포커스가 있을 때만 키가 잡힌다(수동 트리거의 특성).
    """
    if not HAVE_KB:
        return False
    quit_requested = False
    while msvcrt.kbhit():
        ch = msvcrt.getwch()
        if ch in ("\x00", "\xe0"):        # 화살표 등 특수키 접두 → 다음 바이트 버림
            if msvcrt.kbhit():
                msvcrt.getwch()
            continue
        cmd, want_quit = key_action(ch)
        if cmd is not None:
            reasons = {"H": "수동: 귀가", "F": "수동: 주행",
                       "S": "수동: 정지", "?": "수동: 상태 요청"}
            send_to_robot(ser, cmd, reasons.get(cmd, "수동"))
        if want_quit:
            quit_requested = True
    return quit_requested


# ---------------------------------------------------------------------------
#  메인 루프
# ---------------------------------------------------------------------------
def main() -> None:
    bridge_dir = find_bridge_dir()
    print(f"[브리지] 우편함 = {bridge_dir}")
    print("[브리지] 방향 A: 로봇 'ARRIVED' → 펫 exit_home")
    print("[브리지] 방향 B: 펫 state=home → 로봇 'F'(주행)")
    if HAVE_KB:
        print("[키] h=귀가  f=주행  s=정지  ?=상태  q/Esc=종료  "
              "(이 창에 포커스를 두고 눌러라)")
    else:
        print("[키] 이 OS에선 키보드 트리거 비활성 (Ctrl+C 로 종료)")

    # 시작 시점의 state를 기준값으로 삼는다(시작만으로는 'F'를 쏘지 않음).
    # 이후 virtual→home 으로 "바뀔 때"만 로봇을 깨운다.
    last_state = read_state(bridge_dir) or ""

    ser = None
    buf = b""
    next_state_check = 0.0

    while True:
        # 포트가 없으면 연결(재연결)을 시도한다.
        if ser is None:
            ser = connect()
            if ser is None:
                time.sleep(3)  # 연결 대기 (이 구간의 종료는 Ctrl+C)
                continue
            buf = b""
            # 연결 직후: 이미 펫이 볼 안(home)이면 로봇을 바로 주행시킨다.
            cur = read_state(bridge_dir)
            if cur is not None:
                last_state = cur
                if cur == "home":
                    send_to_robot(ser, "F", "펫이 이미 집 안 → 로봇 주행")

        # --- 방향 A: 로봇이 보낸 줄을 읽는다 ---
        try:
            data = ser.read(256)
        except Exception as e:
            print(f"[끊김] 시리얼 오류: {e}. 재연결 시도...")
            try:
                ser.close()
            except Exception:
                pass
            ser = None
            time.sleep(1)
            continue

        if data:
            buf += data
            while b"\n" in buf:
                raw, buf = buf.split(b"\n", 1)
                text = raw.decode("utf-8", "replace").strip()
                if not text:
                    continue
                print(f"[로봇 →] {text}")
                # 로봇은 도착 순간 딱 한 번 "ARRIVED"를 보낸다(main_robot.ino).
                if "ARRIVED" in text.upper():
                    send_to_pet(bridge_dir, "exit_home")

        # --- 방향 B: state 파일이 "home"으로 바뀌면 로봇을 주행시킨다 ---
        now = time.monotonic()
        if now >= next_state_check:
            next_state_check = now + STATE_POLL_SEC
            cur = read_state(bridge_dir)
            if cur is not None and cur != last_state:
                print(f"[state] {last_state or '(없음)'} → {cur}")
                if cur == "home":
                    send_to_robot(ser, "F", "펫이 집에 들어감 → 로봇 자유 주행")
                # (5단계) elif cur == "virtual": send_to_robot(ser, "S", ...)
                last_state = cur

        # --- 수동 트리거: 키보드 (h→H 로 로봇을 집으로 부른다) ---
        if poll_keyboard(ser):
            print("[종료] 키 입력으로 브리지 정지")
            break

        time.sleep(0.01)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[종료] 브리지 정지")
