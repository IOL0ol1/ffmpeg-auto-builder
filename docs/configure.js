// Composable FFmpeg configure options.
// The build runners install no third-party libraries, so every option here only uses
// features built into FFmpeg itself.

export const PRESETS = [
  {
    id: 'general',
    label: '通用（推荐）',
    description: '完整功能，去掉调试信息，适合日常转码和命令行使用。',
    flags: ['--disable-debug'],
  },
  {
    id: 'small',
    label: '体积优先',
    description: '以体积为目标优化（-Os）并禁用网络协议，适合随应用分发命令行工具。',
    flags: ['--disable-debug', '--enable-small', '--disable-network'],
  },
  {
    id: 'libs',
    label: '仅开发库',
    description: '只编译 libav* 库和头文件，不生成 ffmpeg / ffprobe，适合集成到自己的程序中。',
    flags: ['--disable-debug', '--disable-programs'],
  },
  {
    id: 'player',
    label: '播放器解码精简',
    description:
      '仅库，只保留主流格式的解码与解封装：H.264 / HEVC / VP8 / VP9、AAC / MP3 / Opus / Vorbis / FLAC，' +
      'MP4 / MKV / WebM / MP3 / OGG / FLAC / WAV，本地文件读取。',
    flags: [
      '--disable-debug',
      '--disable-programs',
      '--disable-everything',
      '--enable-decoder=h264,hevc,vp8,vp9,aac,mp3,opus,vorbis,flac,pcm_s16le',
      '--enable-demuxer=mov,matroska,mp3,ogg,flac,wav',
      '--enable-parser=h264,hevc,vp8,vp9,aac,mpegaudio,opus,vorbis,flac',
      '--enable-protocol=file',
    ],
  },
  {
    id: 'debug',
    label: '调试符号版',
    description: '保留完整调试信息且不剥离符号，便于用 gdb / lldb 排查问题，体积较大。',
    flags: ['--enable-debug=3', '--disable-stripping'],
  },
];

export const LINKAGES = [
  { id: 'static', label: '静态（单文件可执行）', flags: ['--enable-static', '--disable-shared'] },
  { id: 'shared', label: '共享库（.so / .dylib / .dll）', flags: ['--enable-shared', '--disable-static'] },
  { id: 'both', label: '静态 + 共享', flags: ['--enable-static', '--enable-shared'] },
];

export const LICENSES = [
  { id: 'lgpl', label: 'LGPL（可闭源链接）', flags: [] },
  { id: 'gpl', label: 'GPL v2+', flags: ['--enable-gpl'] },
  { id: 'gpl3', label: 'GPL v3', flags: ['--enable-gpl', '--enable-version3'] },
];

export const EXTRAS = [
  { id: 'nodoc', label: '不生成文档', flags: ['--disable-doc'] },
  { id: 'small', label: '体积优先（-Os）', flags: ['--enable-small'] },
  { id: 'nonetwork', label: '禁用网络协议', flags: ['--disable-network'] },
  { id: 'noavdevice', label: '不编译 libavdevice', flags: ['--disable-avdevice'] },
  { id: 'pic', label: '位置无关代码（PIC）', flags: ['--enable-pic'] },
  { id: 'noautodetect', label: '不自动探测系统库', flags: ['--disable-autodetect'] },
];

export const DEFAULT_CONFIG = {
  preset: 'general',
  linkage: 'static',
  license: 'gpl',
  extras: ['nodoc'],
  custom: '',
};

export const SAFE_TOKEN_PATTERN = /^[-+./:=,@%A-Za-z0-9_]+$/;

// Options that may legitimately repeat with different values, e.g. --enable-decoder=aac.
const COMPONENT_OPTIONS = new Set([
  'decoder', 'encoder', 'demuxer', 'muxer', 'parser', 'protocol', 'filter', 'bsf', 'indev', 'outdev', 'hwaccel',
]);

// Tokens with the same key override each other; the later one wins.
function tokenKey(token) {
  const toggle = token.match(/^--(?:enable|disable)-([^=]+)(?:=.*)?$/);
  if (toggle) {
    return COMPONENT_OPTIONS.has(toggle[1]) && token.includes('=') ? token : `toggle:${toggle[1]}`;
  }
  const valued = token.match(/^--([^=]+)=/);
  return valued ? `option:${valued[1]}` : token;
}

export function splitTokens(text) {
  return String(text || '').split(/\s+/).filter(Boolean);
}

export function mergeTokens(tokens) {
  const merged = new Map();
  tokens.forEach((token) => {
    const key = tokenKey(token);
    merged.delete(key);
    merged.set(key, token);
  });
  return [...merged.values()];
}

function findFlags(list, id) {
  return list.find((item) => item.id === id)?.flags || [];
}

// Order matters: preset → linkage → license → extras → custom, so later groups override earlier ones.
export function buildConfigure(config) {
  const custom = splitTokens(config.custom);
  const tokens = mergeTokens([
    ...findFlags(PRESETS, config.preset),
    ...findFlags(LINKAGES, config.linkage),
    ...findFlags(LICENSES, config.license),
    ...EXTRAS.filter((extra) => config.extras.includes(extra.id)).flatMap((extra) => extra.flags),
    ...custom,
  ]);

  const warnings = [];
  const unsafe = custom.filter((token) => !SAFE_TOKEN_PATTERN.test(token));
  if (unsafe.length) {
    warnings.push({ level: 'error', text: `自定义参数含有不允许的字符：${unsafe.join(' ')}` });
  }
  const external = tokens.filter((token) => /^--enable-lib/.test(token));
  if (external.length) {
    warnings.push({
      level: 'warn',
      text: `${external.join(' ')}：编译环境未安装第三方库，configure 会失败（需在 Fork 中自行添加依赖）。`,
    });
  }
  if (tokens.includes('--enable-nonfree')) {
    warnings.push({ level: 'warn', text: '--enable-nonfree：生成的产物不可再分发。' });
  }

  return { options: tokens.join(' '), tokens, warnings };
}
