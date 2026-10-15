// Visual model of FFmpeg configure options.
// The build runners install no third-party libraries, so every option here only uses
// features built into FFmpeg itself.

// Mutually exclusive choices, rendered as segmented controls.
export const SEGMENTS = [
  {
    id: 'buildType',
    label: '构建类型',
    default: 'release',
    options: [
      { id: 'release', label: 'Release', hint: '完整优化，不含调试信息，体积最小。', flags: ['--disable-debug'] },
      {
        id: 'relwithdebinfo',
        label: 'RelWithDebInfo',
        hint: '完整优化并保留调试符号，便于分析崩溃堆栈。',
        flags: ['--disable-stripping'],
      },
      {
        id: 'debug',
        label: 'Debug',
        hint: '降低优化级别并保留完整调试信息，适合单步调试（FFmpeg 不支持 -O0，仍保留最低限度优化）。',
        flags: ['--enable-debug=3', '--disable-optimizations', '--disable-stripping'],
      },
    ],
  },
  {
    id: 'linkage',
    label: '链接方式',
    default: 'static',
    options: [
      { id: 'static', label: '静态', hint: '生成静态库，ffmpeg / ffprobe 为独立的单文件程序。', flags: ['--enable-static', '--disable-shared'] },
      { id: 'shared', label: '共享', hint: '生成 .so / .dylib / .dll 共享库，程序依赖同目录下的库文件。', flags: ['--enable-shared', '--disable-static'] },
      { id: 'both', label: '静态 + 共享', hint: '同时生成静态库和共享库。', flags: ['--enable-static', '--enable-shared'] },
    ],
  },
  {
    id: 'license',
    label: '许可证',
    default: 'gpl',
    options: [
      {
        id: 'lgpl',
        label: 'LGPL',
        hint: 'LGPL v2.1+，可闭源动态链接；仅限 GPL 的组件会被排除。',
        flags: [],
      },
      {
        id: 'gpl',
        label: 'GPL',
        hint: 'GPL v2+，可用仅限 GPL 的组件，衍生程序需开源。',
        flags: ['--enable-gpl'],
      },
      { id: 'gpl3', label: 'GPL v3', hint: 'GPL v3，额外启用要求 v3 的组件。', flags: ['--enable-gpl', '--enable-version3'] },
    ],
  },
];

// On/off switches. `on` / `off` are the flags emitted for each state;
// `ffmpegDefault` is FFmpeg's own default, used when importing a command line.
export const TOGGLE_GROUPS = [
  {
    id: 'programs',
    label: '程序与库',
    items: [
      { id: 'ffmpeg', label: 'ffmpeg', hint: '转码命令行程序', default: true, ffmpegDefault: true, off: ['--disable-ffmpeg'] },
      { id: 'ffprobe', label: 'ffprobe', hint: '媒体信息分析程序', default: true, ffmpegDefault: true, off: ['--disable-ffprobe'] },
      { id: 'avdevice', label: 'libavdevice', hint: '采集 / 播放设备（摄像头、屏幕等）', default: true, ffmpegDefault: true, off: ['--disable-avdevice'] },
      { id: 'avfilter', label: 'libavfilter', hint: '音视频滤镜，ffmpeg 程序依赖它', default: true, ffmpegDefault: true, off: ['--disable-avfilter'] },
      { id: 'swscale', label: 'libswscale', hint: '图像缩放与像素格式转换', default: true, ffmpegDefault: true, off: ['--disable-swscale'] },
      { id: 'swresample', label: 'libswresample', hint: '音频重采样与格式转换', default: true, ffmpegDefault: true, off: ['--disable-swresample'] },
      { id: 'doc', label: '文档 / man 页', hint: '生成 HTML 文档与 man 页，会增加编译时间', default: false, ffmpegDefault: true, off: ['--disable-doc'] },
    ],
  },
  {
    id: 'features',
    label: '功能特性',
    items: [
      { id: 'asm', label: '汇编优化', hint: 'SIMD 汇编加速；关闭后便于调试但明显变慢', default: true, ffmpegDefault: true, off: ['--disable-asm'] },
      { id: 'hwaccel', label: '硬件加速', hint: '自动启用平台可用的硬件解码（VideoToolbox、D3D11VA、DXVA2 等）', default: true, ffmpegDefault: true, off: ['--disable-hwaccels'] },
      { id: 'network', label: '网络协议', hint: 'http、rtmp、tcp、udp 等网络协议', default: true, ffmpegDefault: true, off: ['--disable-network'] },
      { id: 'autodetect', label: '自动探测系统库', hint: '自动启用系统中可用的库；关闭后产物依赖更少、更可移植', default: true, ffmpegDefault: true, off: ['--disable-autodetect'] },
      { id: 'small', label: '体积优化 (-Os)', hint: '以体积为目标优化，速度略慢', default: false, ffmpegDefault: false, on: ['--enable-small'] },
      { id: 'pic', label: '位置无关代码 (PIC)', hint: '静态库需要链接进其它共享库时开启', default: false, ffmpegDefault: false, on: ['--enable-pic'] },
    ],
  },
];

// Component whitelists used in "slim" mode (--disable-everything + --enable-<kind>=...).
// `gplOnly` lists components whose FFmpeg dependency is "gpl"; configure drops them under LGPL.
export const COMPONENT_GROUPS = [
  {
    id: 'decoder',
    label: '解码器',
    items: ['h264', 'hevc', 'vp8', 'vp9', 'mpeg4', 'mpeg2video', 'mjpeg', 'png', 'gif', 'aac', 'mp3', 'opus', 'vorbis', 'flac', 'alac', 'ac3', 'pcm_s16le'],
    defaults: ['h264', 'hevc', 'vp9', 'aac', 'mp3', 'opus', 'flac', 'pcm_s16le'],
  },
  {
    id: 'encoder',
    label: '编码器',
    items: ['mpeg4', 'mjpeg', 'png', 'gif', 'ffv1', 'aac', 'flac', 'ac3', 'opus', 'pcm_s16le'],
    defaults: ['aac', 'pcm_s16le'],
  },
  {
    id: 'demuxer',
    label: '解封装（输入格式）',
    items: ['mov', 'matroska', 'mpegts', 'flv', 'avi', 'mp3', 'aac', 'ogg', 'flac', 'wav', 'hls', 'image2', 'gif', 'concat'],
    defaults: ['mov', 'matroska', 'mpegts', 'mp3', 'aac', 'ogg', 'flac', 'wav'],
  },
  {
    id: 'muxer',
    label: '封装（输出格式）',
    items: ['mp4', 'mov', 'matroska', 'webm', 'mpegts', 'flv', 'hls', 'segment', 'mp3', 'adts', 'ogg', 'flac', 'wav', 'image2', 'gif'],
    defaults: ['mp4', 'matroska', 'mpegts', 'adts', 'wav'],
  },
  {
    id: 'parser',
    label: '解析器',
    items: ['h264', 'hevc', 'vp8', 'vp9', 'av1', 'mpeg4video', 'mjpeg', 'png', 'aac', 'mpegaudio', 'opus', 'vorbis', 'flac', 'ac3'],
    defaults: ['h264', 'hevc', 'vp9', 'aac', 'mpegaudio', 'opus', 'flac'],
  },
  {
    id: 'bsf',
    label: '比特流滤镜',
    items: ['h264_mp4toannexb', 'hevc_mp4toannexb', 'aac_adtstoasc', 'extract_extradata', 'vp9_superframe'],
    defaults: ['h264_mp4toannexb', 'hevc_mp4toannexb', 'aac_adtstoasc'],
  },
  {
    id: 'protocol',
    label: '协议',
    items: ['file', 'pipe', 'data', 'concat', 'crypto', 'http', 'https', 'tcp', 'udp', 'rtmp', 'hls'],
    defaults: ['file', 'pipe'],
  },
  {
    id: 'filter',
    label: '滤镜',
    items: ['scale', 'format', 'null', 'copy', 'crop', 'pad', 'transpose', 'hflip', 'vflip', 'fps', 'setpts', 'trim', 'overlay',
      'hqdn3d', 'delogo', 'eq', 'cropdetect', 'mpdecimate',
      'anull', 'acopy', 'aformat', 'aresample', 'volume', 'asetpts', 'atrim', 'amix', 'concat'],
    defaults: ['scale', 'format', 'null', 'copy', 'anull', 'acopy', 'aformat', 'aresample'],
    gplOnly: ['hqdn3d', 'delogo', 'eq', 'cropdetect', 'mpdecimate'],
  },
];

export const SAFE_TOKEN_PATTERN = /^[-+./:=,@%A-Za-z0-9_]+$/;

export function defaultConfig() {
  return {
    ...Object.fromEntries(SEGMENTS.map((segment) => [segment.id, segment.default])),
    toggles: Object.fromEntries(TOGGLE_GROUPS.flatMap((group) => group.items).map((item) => [item.id, item.default])),
    componentMode: 'all',
    components: Object.fromEntries(COMPONENT_GROUPS.map((group) => [group.id, [...group.defaults]])),
    custom: '',
  };
}

// Fill gaps in a stored or partial config so older saved states keep working.
export function normalizeConfig(raw) {
  const base = defaultConfig();
  const config = { ...base, ...(raw || {}) };
  SEGMENTS.forEach((segment) => {
    if (!segment.options.some((option) => option.id === config[segment.id])) config[segment.id] = segment.default;
  });
  config.toggles = { ...base.toggles, ...(raw?.toggles || {}) };
  config.componentMode = config.componentMode === 'slim' ? 'slim' : 'all';
  config.components = { ...base.components, ...(raw?.components || {}) };
  config.custom = String(config.custom || '');
  return config;
}

// Options that may legitimately repeat with different values, e.g. --enable-decoder=aac.
const COMPONENT_KINDS = new Set(['decoder', 'encoder', 'demuxer', 'muxer', 'parser', 'protocol', 'filter', 'bsf', 'indev', 'outdev', 'hwaccel']);

// Tokens with the same key override each other; the later one wins.
function tokenKey(token) {
  const toggle = token.match(/^--(?:enable|disable)-([^=]+)(?:=.*)?$/);
  if (toggle) {
    return COMPONENT_KINDS.has(toggle[1]) && token.includes('=') ? token : `toggle:${toggle[1]}`;
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

export function toggleFlags(item, enabled) {
  return (enabled ? item.on : item.off) || [];
}

export function requiresGpl(group, name) {
  return Boolean(group.gplOnly?.includes(name));
}

export function isComponentAvailable(config, group, name) {
  return config.license !== 'lgpl' || !requiresGpl(group, name);
}

// Selected components that the current license allows; the stored selection is kept
// so switching back to GPL restores it.
export function effectiveComponents(config, group) {
  return (config.components[group.id] || []).filter((name) => isComponentAvailable(config, group, name));
}

// Order: segments → toggles → components → custom; later tokens override earlier ones.
export function buildConfigure(config) {
  const custom = splitTokens(config.custom);
  const tokens = mergeTokens([
    ...SEGMENTS.flatMap((segment) => segment.options.find((option) => option.id === config[segment.id])?.flags || []),
    ...TOGGLE_GROUPS.flatMap((group) => group.items).flatMap((item) => toggleFlags(item, config.toggles[item.id])),
    ...(config.componentMode === 'slim'
      ? ['--disable-everything', ...COMPONENT_GROUPS
        .map((group) => [group, effectiveComponents(config, group)])
        .filter(([, names]) => names.length)
        .map(([group, names]) => `--enable-${group.id}=${names.join(',')}`)]
      : []),
    ...custom,
  ]);

  return { options: tokens.join(' '), tokens, warnings: collectWarnings(config, tokens, custom) };
}

function collectWarnings(config, tokens, custom) {
  const warnings = [];
  const error = (text) => warnings.push({ level: 'error', text });
  const warn = (text) => warnings.push({ level: 'warn', text });
  const info = (text) => warnings.push({ level: 'info', text });

  const unsafe = custom.filter((token) => !SAFE_TOKEN_PATTERN.test(token));
  if (unsafe.length) error(`自定义参数含有不允许的字符：${unsafe.join(' ')}`);
  if (tokens.some((token) => token.startsWith('--prefix='))) {
    error('不能指定 --prefix：安装路径由编译流程管理，产物会自动打包。');
  }

  const external = tokens.filter((token) => /^--enable-lib/.test(token));
  if (external.length) {
    warn(`${external.join(' ')}：编译环境未安装第三方库，configure 会失败（需在 Fork 中自行添加依赖）。`);
  }
  if (tokens.includes('--enable-nonfree')) warn('--enable-nonfree：生成的产物不可再分发。');

  const has = (flag) => tokens.includes(flag);
  if (!has('--disable-ffmpeg') && has('--disable-avfilter')) {
    warn('ffmpeg 程序依赖 libavfilter，关闭 libavfilter 后不会生成 ffmpeg。');
  }
  if (has('--disable-ffmpeg') && has('--disable-ffprobe')) info('未选择任何程序，将只生成库和头文件。');

  if (config.componentMode === 'slim') {
    const selected = (id) => effectiveComponents(config, COMPONENT_GROUPS.find((group) => group.id === id));
    const dropped = COMPONENT_GROUPS.flatMap((group) => (config.components[group.id] || [])
      .filter((name) => !isComponentAvailable(config, group, name)));
    if (dropped.length) info(`LGPL 许可证下已排除仅限 GPL 的组件：${dropped.join('、')}。`);
    if (!selected('protocol').length) warn('精简模式下未选择任何协议，将无法读写文件（至少保留 file）。');
    if (!selected('decoder').length && !selected('encoder').length) {
      warn('精简模式下未选择任何编解码器，只能做封装格式转换。');
    }
    if (selected('protocol').includes('https')) {
      info('https 需要 TLS 支持：macOS / Windows 使用系统 TLS，Linux 编译环境未安装 TLS 库，该协议不会被编译进去。');
    }
  }
  return warnings;
}

// Map an existing configure command line onto the visual controls.
// Tokens that no control represents are returned in `custom`.
export function importConfigure(text) {
  // --disable-programs is shorthand for disabling every program toggle.
  const remaining = splitTokens(text)
    .filter((token) => token !== './configure')
    .flatMap((token) => (token === '--disable-programs' ? ['--disable-ffmpeg', '--disable-ffprobe'] : [token]));
  const config = defaultConfig();
  const has = (flag) => remaining.includes(flag);
  const take = (...flags) => flags.forEach((flag) => {
    const index = remaining.indexOf(flag);
    if (index >= 0) remaining.splice(index, 1);
  });

  // Build type
  const debugFlag = remaining.find((token) => /^--enable-debug(=.*)?$/.test(token));
  if (debugFlag || has('--disable-optimizations')) {
    config.buildType = 'debug';
    take(debugFlag, '--disable-optimizations', '--disable-stripping');
  } else if (has('--disable-debug')) {
    config.buildType = 'release';
    take('--disable-debug');
  } else {
    config.buildType = 'relwithdebinfo';
    take('--disable-stripping');
  }

  // Linkage (FFmpeg defaults to static only)
  const shared = has('--enable-shared');
  const noStatic = has('--disable-static');
  config.linkage = shared ? (noStatic ? 'shared' : 'both') : 'static';
  take('--enable-shared', '--disable-shared', '--enable-static', '--disable-static');

  // License
  if (has('--enable-gpl')) {
    config.license = has('--enable-version3') ? 'gpl3' : 'gpl';
    take('--enable-gpl', '--enable-version3');
  } else {
    config.license = 'lgpl';
  }

  // Toggles: absent flags mean FFmpeg's default
  TOGGLE_GROUPS.flatMap((group) => group.items).forEach((item) => {
    const off = item.off || [];
    const on = item.on || [];
    if (off.length && off.every(has)) {
      config.toggles[item.id] = false;
    } else if (on.length && on.every(has)) {
      config.toggles[item.id] = true;
    } else {
      config.toggles[item.id] = item.ffmpegDefault;
    }
    take(...off, ...on);
  });

  // Components
  if (has('--disable-everything')) {
    config.componentMode = 'slim';
    take('--disable-everything');
    COMPONENT_GROUPS.forEach((group) => {
      config.components[group.id] = [];
      const prefix = `--enable-${group.id}=`;
      remaining.filter((token) => token.startsWith(prefix)).forEach((token) => {
        const names = token.slice(prefix.length).split(',').filter(Boolean);
        const known = names.filter((name) => group.items.includes(name));
        const unknown = names.filter((name) => !group.items.includes(name));
        config.components[group.id] = [...new Set([...config.components[group.id], ...known])];
        const index = remaining.indexOf(token);
        if (unknown.length) {
          remaining.splice(index, 1, `${prefix}${unknown.join(',')}`);
        } else {
          remaining.splice(index, 1);
        }
      });
    });
  }

  config.custom = remaining.join(' ');
  return config;
}
