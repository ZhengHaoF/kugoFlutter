"""Probe user collections APIs used by 我喜欢 page.

Mirrors app/lib/data/repositories/user_repository.dart:
  POST /v7/get_all_list
  POST /v4/get_list_all_file_v3
  POST /v4/follow_list
"""
from __future__ import annotations

import hashlib
import json
import os
import time
import urllib.error
import urllib.request

TOKEN = os.environ.get(
    "KUGO_TOKEN",
    "4a02e46fe7546861f9db29c410801e32fa2680b2a90cb991468660db572d54f7",
)
USERID = os.environ.get("KUGO_USERID", "2511133520")
GUID = os.environ.get(
    "KUGO_GUID", "2b9c607bf85a801ca492f2d95bb4e67b"
)
DFID = os.environ.get("KUGO_DFID", "0QeBfz1rwip04Bv9cF415aed")
DEV = os.environ.get("KUGO_DEV", "kugoFlutter")

APPID = 3116
CLIENTVER = 11440
SALT_SIG = "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"
UA = "Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi"
GATEWAY = "https://gateway.kugou.com"


def md5(s: str) -> str:
    return hashlib.md5(s.encode("utf-8")).hexdigest()


def mid_from_guid(guid: str) -> str:
    return str(int(md5(guid), 16))


def signature_android(params: dict, data: str = "") -> str:
    parts = "".join(f"{k}={params[k]}" for k in sorted(params))
    return md5(f"{SALT_SIG}{parts}{data}{SALT_SIG}")


def cookie_header(mid: str) -> str:
    return "; ".join(
        [
            f"token={TOKEN}",
            f"userid={USERID}",
            f"dfid={DFID}",
            f"KUGOU_API_MID={mid}",
            f"KUGOU_API_GUID={GUID}",
            f"KUGOU_API_DEV={DEV}",
        ]
    )


def post(label: str, path: str, router: str, body_obj: dict) -> None:
    mid = mid_from_guid(GUID)
    clienttime = int(time.time())
    raw = json.dumps(body_obj, separators=(",", ":"), ensure_ascii=False)
    query = {
        "dfid": DFID,
        "mid": mid,
        "uuid": "-",
        "appid": APPID,
        "clientver": CLIENTVER,
        "clienttime": clienttime,
        "plat": 1,
        "userid": int(USERID),
        "token": TOKEN,
    }
    query["signature"] = signature_android(query, data=raw)
    qs = "&".join(f"{k}={query[k]}" for k in query)
    full = f"{GATEWAY}{path}?{qs}"
    headers = {
        "User-Agent": UA,
        "Content-Type": "application/json",
        "dfid": DFID,
        "mid": mid,
        "clienttime": str(clienttime),
        "x-router": router,
        "Cookie": cookie_header(mid),
    }
    print(f"\n===== {label} =====")
    print("URL path:", path, "router:", router)
    print("body:", raw[:300])
    req = urllib.request.Request(
        full, data=raw.encode("utf-8"), method="POST", headers=headers
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            text = resp.read().decode("utf-8", errors="replace")
            print("HTTP:", resp.status, "len:", len(text))
            print("body[:1500]:", text[:1500])
            try:
                parsed = json.loads(text)
            except json.JSONDecodeError:
                print("NOT JSON (maybe URL filter / HTML)")
                return
            print("status:", parsed.get("status"))
            print("error_code:", parsed.get("error_code") or parsed.get("err_code"))
            print("msg:", parsed.get("msg") or parsed.get("error") or parsed.get("message"))
            data = parsed.get("data")
            if isinstance(data, dict):
                print("data keys:", list(data.keys())[:40])
                for k in ("info", "lists", "list", "songs", "total", "count"):
                    if k in data:
                        v = data[k]
                        if isinstance(v, list):
                            print(f"  data.{k} len={len(v)}")
                            if v and isinstance(v[0], dict):
                                print(f"  data.{k}[0] keys:", list(v[0].keys())[:30])
                                sample = {
                                    kk: v[0].get(kk)
                                    for kk in (
                                        "listid",
                                        "list_create_listid",
                                        "id",
                                        "name",
                                        "specialname",
                                        "source",
                                        "is_def",
                                        "is_default",
                                        "type",
                                        "count",
                                        "songcount",
                                        "list_create_userid",
                                        "nickname",
                                    )
                                    if kk in v[0]
                                }
                                print(f"  data.{k}[0] sample:", sample)
                        else:
                            print(f"  data.{k} =", v)
            elif isinstance(data, list):
                print("data list len:", len(data))
            else:
                print("data:", type(data).__name__, str(data)[:200])
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print("HTTPError:", e.code)
        print("body[:800]:", body[:800])
    except Exception as e:  # noqa: BLE001
        print("EXC:", type(e).__name__, e)


def main() -> None:
    mid = mid_from_guid(GUID)
    print("mid =", mid)
    print("userid =", USERID)

    post(
        "get_all_list",
        "/v7/get_all_list",
        "cloudlist.service.kugou.com",
        {
            "userid": int(USERID),
            "token": TOKEN,
            "total_ver": 979,
            "type": 2,
            "page": 1,
            "pagesize": 50,
        },
    )

    post(
        "follow_list",
        "/v4/follow_list",
        "relationuser.kugou.com",
        {
            "merge": 2,
            "need_iden_type": 1,
            "ext_params": "k_pic,jumptype,singerid,score",
            "userid": int(USERID),
            "type": 0,
            "id_type": 0,
            "p": "SKIP_RSA_PLACEHOLDER",
        },
    )

    # listid filled after get_all_list if needed; try type=0 empty first
    listid = os.environ.get("KUGO_LISTID", "0")
    post(
        "get_list_all_file_v3",
        "/v4/get_list_all_file_v3",
        "cloudlist.service.kugou.com",
        {
            "listid": int(listid) if listid.isdigit() else listid,
            "userid": int(USERID),
            "type": 0,
            "page": 1,
            "pagesize": 50,
            "area_code": 1,
            "allplatform": 1,
            "show_cover": 1,
            "token": TOKEN,
        },
    )


if __name__ == "__main__":
    main()
