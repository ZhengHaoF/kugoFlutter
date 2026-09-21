"""Probe KuGou /v2/personal_recommend with a logged-in session.

Mirrors app/lib/data/repositories/fm_repository.dart + KuGouMusicApi
module/personal_fm.js so we can see the raw gateway response.

Fill TOKEN / USERID / GUID / DFID from the app's local
SharedPreferences (`flutter.auth.user.v1` + device keys), or from env:
  KUGO_FM_TOKEN, KUGO_FM_USERID, KUGO_FM_GUID, KUGO_FM_DFID
"""
from __future__ import annotations

import hashlib
import json
import os
import time
import urllib.error
import urllib.request

TOKEN = os.environ.get("KUGO_FM_TOKEN", "")
USERID = os.environ.get("KUGO_FM_USERID", "")
GUID = os.environ.get("KUGO_FM_GUID", "")
DFID = os.environ.get("KUGO_FM_DFID", "-")
DEV = "kugoFlutter"

APPID = "3116"
CLIENTVER = "11440"
SALT_SIG = "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"
SALT_KEY = "185672dd44712f60bb1736df5a377e82"
UA = "Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi"
GATEWAY = "https://gateway.kugou.com"
FM_PATH = "/v2/personal_recommend"
FM_ROUTER = "persnfm.service.kugou.com"
EVERYDAY_PATH = "/everyday_song_recommend"
EVERYDAY_ROUTER = "everydayrec.service.kugou.com"


def md5(s: str) -> str:
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def mid_from_guid(guid: str) -> str:
    return str(int(md5(guid), 16))


def sign_params_key(data: str) -> str:
    return md5(f"{APPID}{SALT_SIG}{CLIENTVER}{data}")


def signature_android(params: dict, data: str = "") -> str:
    parts = "".join(f"{k}={params[k]}" for k in sorted(params))
    return md5(f"{SALT_SIG}{parts}{data}{SALT_SIG}")


def post(url: str, query: dict, body_obj: dict, headers: dict, label: str) -> None:
    qs = "&".join(f"{k}={query[k]}" for k in query)
    full = f"{url}?{qs}"
    raw = json.dumps(body_obj, separators=(",", ":"), ensure_ascii=False)
    print(f"\n===== {label} =====")
    print("URL:", full[:180] + ("..." if len(full) > 180 else ""))
    print("x-router:", headers.get("x-router"))
    print("body keys:", sorted(body_obj.keys()))
    print("body sample:", {k: body_obj[k] for k in list(body_obj)[:8]})
    req = urllib.request.Request(
        full,
        data=raw.encode("utf-8"),
        method="POST",
        headers=headers,
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            status = resp.status
            text = resp.read().decode("utf-8", errors="replace")
            print("HTTP:", status)
            print("length:", len(text))
            print("body[:1200]:", text[:1200])
            try:
                parsed = json.loads(text)
                data = parsed.get("data")
                print("error_code:", parsed.get("error_code") or parsed.get("err_code"))
                print("status:", parsed.get("status"))
                print("data type:", type(data).__name__)
                if isinstance(data, str):
                    print("data str len:", len(data), "empty?", data == "")
                elif isinstance(data, list):
                    print("data list len:", len(data))
                    if data:
                        print("first item keys:", list(data[0])[:20] if isinstance(data[0], dict) else data[0])
                elif isinstance(data, dict):
                    print("data dict keys:", list(data.keys())[:30])
                    for k in ("song_list", "songs", "list", "info"):
                        if k in data and isinstance(data[k], list):
                            print(f"  data.{k} len:", len(data[k]))
            except json.JSONDecodeError:
                print("response is not JSON")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print("HTTPError:", e.code)
        print("body[:800]:", body[:800])
    except Exception as e:  # noqa: BLE001
        print("EXC:", type(e).__name__, e)


def main() -> None:
    if not TOKEN or not USERID or not GUID:
        raise SystemExit(
            "Set KUGO_FM_TOKEN / KUGO_FM_USERID / KUGO_FM_GUID "
            "(optional KUGO_FM_DFID) before probing."
        )
    mid = mid_from_guid(GUID)
    print("mid =", mid)
    print("userid =", USERID)
    print("guid =", GUID)

    clienttime = int(time.time())
    userid_num = int(USERID)

    # --- Control: everyday personalized (known-good path with login) ---
    # Mirror recommend_repository style roughly: signed query + cookie + auth body bits.
    everyday_body = {
        "appid": int(APPID),
        "clientver": int(CLIENTVER),
        "clienttime": clienttime,
        "mid": mid,
        "guid": GUID,
        "userid": userid_num,
        "token": TOKEN,
        "area_code": 1,
        "platform": "android",
    }
    everyday_query = {
        "appid": APPID,
        "clientver": CLIENTVER,
        "clienttime": str(clienttime),
        "mid": mid,
        "uuid": "-",
        "dfid": DFID,
    }
    everyday_query["signature"] = signature_android(
        everyday_query, data=json.dumps(everyday_body, separators=(",", ":"), ensure_ascii=False)
    )
    cookie = "; ".join(
        [
            f"token={TOKEN}",
            f"userid={USERID}",
            f"dfid={DFID}",
            f"KUGOU_API_MID={mid}",
            f"KUGOU_API_GUID={GUID}",
            f"KUGOU_API_DEV={DEV}",
        ]
    )
    everyday_headers = {
        "User-Agent": UA,
        "Content-Type": "application/json",
        "dfid": DFID,
        "clienttime": str(clienttime),
        "mid": mid,
        "x-router": EVERYDAY_ROUTER,
        "Cookie": cookie,
    }
    post(f"{GATEWAY}{EVERYDAY_PATH}", everyday_query, everyday_body, everyday_headers, "CONTROL everyday_song_recommend")

    # --- Target A: current app body (kguid=device.guid) ---
    clienttime = int(time.time())
    body_a = {
        "appid": int(APPID),
        "clienttime": clienttime,
        "mid": mid,
        "action": "play",
        "recommend_source_locked": 0,
        "song_pool_id": 0,
        "callerid": 0,
        "m_type": 1,
        "platform": "ios",
        "area_code": 1,
        "remain_songcnt": 0,
        "clientver": int(CLIENTVER),
        "is_overplay": 0,
        "mode": "normal",
        "fakem": "ca981cfc583a4c37f28d2d49000013c16a0a",
        "key": sign_params_key(str(clienttime)),
        "token": TOKEN,
        "userid": userid_num,
        "kguid": GUID,
        "vip_type": 0,
    }
    body_a_json = json.dumps(body_a, separators=(",", ":"), ensure_ascii=False)
    query_a = {
        "dfid": DFID,
        "mid": mid,
        "uuid": "-",
        "appid": APPID,
        "clientver": CLIENTVER,
        "clienttime": str(clienttime),
    }
    query_a["signature"] = signature_android(query_a, data=body_a_json)
    headers_a = {
        "User-Agent": UA,
        "Content-Type": "application/json",
        "dfid": DFID,
        "clienttime": str(clienttime),
        "mid": mid,
        "x-router": FM_ROUTER,
        "Cookie": cookie,
    }
    post(f"{GATEWAY}{FM_PATH}", query_a, body_a, headers_a, "FM current-app (kguid=device.guid)")

    # --- Target B: KuGouMusicApi style (kguid=userid, kguid only if userid) ---
    clienttime = int(time.time())
    body_b = {
        "appid": int(APPID),
        "clienttime": clienttime,
        "mid": mid,
        "action": "play",
        "recommend_source_locked": 0,
        "song_pool_id": 0,
        "callerid": 0,
        "m_type": 1,
        "platform": "ios",
        "area_code": 1,
        "remain_songcnt": 0,
        "clientver": int(CLIENTVER),
        "is_overplay": 0,
        "mode": "normal",
        "fakem": "ca981cfc583a4c37f28d2d49000013c16a0a",
        "key": sign_params_key(str(clienttime)),
        "userid": userid_num,
        "kguid": userid_num,
        "token": TOKEN,
        "vip_type": 0,
    }
    body_b_json = json.dumps(body_b, separators=(",", ":"), ensure_ascii=False)
    query_b = {
        "dfid": DFID,
        "mid": mid,
        "uuid": "-",
        "appid": APPID,
        "clientver": CLIENTVER,
        "clienttime": str(clienttime),
    }
    query_b["signature"] = signature_android(query_b, data=body_b_json)
    post(f"{GATEWAY}{FM_PATH}", query_b, body_b, headers_a, "FM API-style (kguid=userid)")

    # --- Target C: no login fields (guest baseline) ---
    clienttime = int(time.time())
    body_c = {
        "appid": int(APPID),
        "clienttime": clienttime,
        "mid": mid,
        "action": "play",
        "recommend_source_locked": 0,
        "song_pool_id": 0,
        "callerid": 0,
        "m_type": 1,
        "platform": "ios",
        "area_code": 1,
        "remain_songcnt": 0,
        "clientver": int(CLIENTVER),
        "is_overplay": 0,
        "mode": "normal",
        "fakem": "ca981cfc583a4c37f28d2d49000013c16a0a",
        "key": sign_params_key(str(clienttime)),
    }
    body_c_json = json.dumps(body_c, separators=(",", ":"), ensure_ascii=False)
    query_c = {
        "dfid": DFID,
        "mid": mid,
        "uuid": "-",
        "appid": APPID,
        "clientver": CLIENTVER,
        "clienttime": str(clienttime),
    }
    query_c["signature"] = signature_android(query_c, data=body_c_json)
    headers_c = dict(headers_a)
    headers_c["Cookie"] = "; ".join(
        [
            f"dfid={DFID}",
            f"KUGOU_API_MID={mid}",
            f"KUGOU_API_GUID={GUID}",
            f"KUGOU_API_DEV={DEV}",
        ]
    )
    post(f"{GATEWAY}{FM_PATH}", query_c, body_c, headers_c, "FM guest (no token)")


if __name__ == "__main__":
    main()
