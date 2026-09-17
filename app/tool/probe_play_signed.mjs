import crypto from 'crypto';

const md5 = (s) => crypto.createHash('md5').update(String(s), 'utf8').digest('hex');

const appid = '3116';
const clientver = '11440';
const saltKey = '185672dd44712f60bb1736df5a377e82';
const saltSig = 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA';

const randomString = (len = 24) => {
  const pool = '1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  let out = '';
  for (let i = 0; i < len; i++) out += pool[Math.ceil((pool.length - 1) * Math.random())];
  return out;
};

const calculateMid = (str) => {
  const digest = md5(str);
  return BigInt('0x' + digest).toString();
};

const signatureAndroidParams = (params, data = '') => {
  const paramsString = Object.keys(params)
    .sort()
    .map((key) => `${key}=${typeof params[key] === 'object' ? JSON.stringify(params[key]) : params[key]}`)
    .join('');
  return md5(`${saltSig}${paramsString}${data || ''}${saltSig}`);
};

const signKey = (hash, mid, userid = 0) => md5(`${hash}${saltKey}${appid}${mid}${userid || 0}`);

async function probe(label, hash, albumId = 0, albumAudioId = 0) {
  const dfid = randomString(24);
  const guid = md5(`kugo-${Date.now()}-${Math.random()}`);
  const mid = calculateMid(guid);
  const clienttime = Math.floor(Date.now() / 1000);
  const hashL = String(hash).toLowerCase();

  const params = {
    album_id: Number(albumId ?? 0),
    area_code: 1,
    hash: hashL,
    ssa_flag: 'is_fromtrack',
    version: 11430,
    page_id: 967177915,
    quality: 128,
    album_audio_id: Number(albumAudioId ?? 0),
    behavior: 'play',
    pid: 411,
    cmd: 26,
    pidversion: 3001,
    IsFreePart: 0,
    ppage_id: '356753938,823673182,967485191',
    cdnBackup: 1,
    module: '',
    clientver: Number(clientver),
    appid: Number(appid),
    clienttime,
    dfid,
    mid,
    uuid: '-',
    key: signKey(hashL, mid, 0),
  };
  params.signature = signatureAndroidParams(params);

  const qs = Object.keys(params)
    .map((k) => `${k}=${encodeURIComponent(params[k])}`)
    .join('&');

  const headers = {
    'User-Agent': 'Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi',
    dfid,
    clienttime: String(clienttime),
    mid,
    'kg-rc': '1',
    'kg-thash': '5d816a0',
    'kg-rec': '1',
    'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
  };

  const urls = [
    { label: 'gateway+router', url: `https://gateway.kugou.com/v5/url?${qs}`, h: { ...headers, 'x-router': 'trackercdn.kugou.com' } },
    { label: 'tracker-http', url: `http://trackercdn.kugou.com/v5/url?${qs}`, h: headers },
    { label: 'tracker-https', url: `https://trackercdn.kugou.com/v5/url?${qs}`, h: headers },
  ];

  for (const item of urls) {
    try {
      const res = await fetch(item.url, { headers: item.h });
      const text = await res.text();
      console.log(`[${label}][${item.label}] ${res.status}`);
      console.log(text.slice(0, 800));
    } catch (e) {
      console.log(`[${label}][${item.label}] ERR ${e.message}`);
    }
    console.log('---');
  }
}

const hash = process.argv[2] || '1d4ca6f82e46debfc3549bb157bb7edd';
const album = process.argv[3] || '81010330';
await probe('free-ish', hash, album, 0);
