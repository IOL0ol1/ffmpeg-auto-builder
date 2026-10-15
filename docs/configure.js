// Visual model of FFmpeg configure options.
// The build runners install no third-party libraries, so every option here only uses
// features built into FFmpeg itself. Invalid combinations are made unselectable in the
// UI (disabled options, linked dependencies) instead of being validated after the fact.

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
    // No built-in component requires version3; it only matters for third-party libraries,
    // so GPL v3 is not offered (--enable-version3 can still be added as a custom flag).
    id: 'license',
    label: '许可证',
    default: 'gpl',
    options: [
      { id: 'lgpl', label: 'LGPL', hint: 'LGPL v2.1+，可闭源动态链接；仅限 GPL 的组件不可选。', flags: [] },
      { id: 'gpl', label: 'GPL', hint: 'GPL v2+，可用仅限 GPL 的组件，衍生程序需开源。', flags: ['--enable-gpl'] },
    ],
  },
];

// On/off switches. `on` / `off` are the flags emitted for each state;
// `requires` lists toggles that must stay enabled while this one is enabled.
export const TOGGLE_GROUPS = [
  {
    id: 'programs',
    label: '程序与库',
    items: [
      { id: 'ffmpeg', label: 'ffmpeg', hint: '转码命令行程序（依赖 libavfilter）', default: true, off: ['--disable-ffmpeg'], requires: ['avfilter'] },
      { id: 'ffprobe', label: 'ffprobe', hint: '媒体信息分析程序', default: true, off: ['--disable-ffprobe'] },
      { id: 'avdevice', label: 'libavdevice', hint: '采集 / 播放设备（摄像头、屏幕等）', default: true, off: ['--disable-avdevice'] },
      { id: 'avfilter', label: 'libavfilter', hint: '音视频滤镜', default: true, off: ['--disable-avfilter'] },
      { id: 'swscale', label: 'libswscale', hint: '图像缩放与像素格式转换', default: true, off: ['--disable-swscale'] },
      { id: 'swresample', label: 'libswresample', hint: '音频重采样与格式转换', default: true, off: ['--disable-swresample'] },
      { id: 'doc', label: '文档 / man 页', hint: '生成 HTML 文档与 man 页，会增加编译时间', default: false, off: ['--disable-doc'] },
    ],
  },
  {
    id: 'features',
    label: '功能特性',
    items: [
      { id: 'asm', label: '汇编优化', hint: 'SIMD 汇编加速；关闭后便于调试但明显变慢', default: true, off: ['--disable-asm'] },
      { id: 'hwaccel', label: '硬件加速', hint: '自动启用平台可用的硬件解码（VideoToolbox、D3D11VA、DXVA2 等）', default: true, off: ['--disable-hwaccels'] },
      { id: 'network', label: '网络协议', hint: 'http、rtmp、tcp、udp 等网络协议', default: true, off: ['--disable-network'] },
      { id: 'autodetect', label: '自动探测系统库', hint: '自动启用系统中可用的库；关闭后产物依赖更少、更可移植', default: true, off: ['--disable-autodetect'] },
      { id: 'small', label: '体积优化 (-Os)', hint: '以体积为目标优化，速度略慢', default: false, on: ['--enable-small'] },
      { id: 'pic', label: '位置无关代码 (PIC)', hint: '静态库需要链接进其它共享库时开启', default: false, on: ['--enable-pic'] },
    ],
  },
];

const TOGGLES = TOGGLE_GROUPS.flatMap((group) => group.items);
const toggleById = (id) => TOGGLES.find((item) => item.id === id);

// Component whitelists used in "slim" mode (--disable-everything + --enable-<kind>=...).
// `locked` items are always included in slim mode; `rules` make items unavailable:
//   gpl: needs the GPL license; needs: needs a library toggle; platforms: target platforms
//   where the item can actually be built.
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
    locked: ['file'],
    rules: {
      https: { platforms: ['macos', 'windows'], reason: 'Linux 编译环境没有 TLS 库，仅 macOS / Windows 可用' },
    },
  },
  {
    id: 'filter',
    label: '滤镜',
    items: ['scale', 'format', 'null', 'copy', 'crop', 'pad', 'transpose', 'hflip', 'vflip', 'fps', 'setpts', 'trim', 'overlay',
      'hqdn3d', 'delogo', 'eq', 'cropdetect', 'mpdecimate',
      'anull', 'acopy', 'aformat', 'aresample', 'volume', 'asetpts', 'atrim', 'amix', 'concat'],
    defaults: ['scale', 'format', 'null', 'copy', 'anull', 'acopy', 'aformat', 'aresample'],
    rules: {
      scale: { needs: 'swscale' },
      aresample: { needs: 'swresample' },
      hqdn3d: { gpl: true },
      delogo: { gpl: true },
      eq: { gpl: true },
      cropdetect: { gpl: true },
      mpdecimate: { gpl: true },
    },
  },
];

const componentGroup = (id) => COMPONENT_GROUPS.find((group) => group.id === id);

export const SAFE_TOKEN_PATTERN = /^[-+./:=,@%A-Za-z0-9_]+$/;

export function defaultConfig() {
  return {
    ...Object.fromEntries(SEGMENTS.map((segment) => [segment.id, segment.default])),
    toggles: Object.fromEntries(TOGGLES.map((item) => [item.id, item.default])),
    componentMode: 'all',
    components: Object.fromEntries(COMPONENT_GROUPS.map((group) => [group.id, [...group.defaults]])),
    custom: '',
  };
}

// A pasted "./configure ..." line is accepted; the command name itself is dropped.
export function splitTokens(text) {
  return String(text || '').split(/\s+/).filter((token) => token && token !== './configure' && token !== 'configure');
}

// Custom flags are free text; characters outside the safe set are simply removed.
export function sanitizeCustom(text) {
  return String(text || '').replace(/[^-+./:=,@%A-Za-z0-9_\s]/g, '');
}

// Fill gaps in a stored or partial config so older saved states keep working.
export function normalizeConfig(raw) {
  const base = defaultConfig();
  const config = { ...base, ...(raw || {}) };
  let custom = sanitizeCustom(Array.isArray(raw?.custom) ? raw.custom.join(' ') : raw?.custom);
  if (config.license === 'gpl3') {
    // GPL v3 is no longer offered; keep the saved build identical.
    config.license = 'gpl';
    custom = `${custom} --enable-version3`.trim();
  }
  SEGMENTS.forEach((segment) => {
    if (!segment.options.some((option) => option.id === config[segment.id])) config[segment.id] = segment.default;
  });
  config.toggles = { ...base.toggles, ...(raw?.toggles || {}) };
  config.componentMode = config.componentMode === 'slim' ? 'slim' : 'all';
  config.components = { ...base.components, ...(raw?.components || {}) };
  config.custom = custom;
  return config;
}

// ── Availability ─────────────────────────────────────────────────────────────

// context: { platform } — the selected target platform ("all" allows everything).
export function componentStatus(config, context, groupId, name) {
  const group = componentGroup(groupId);
  if (group.locked?.includes(name)) {
    return { available: true, locked: true, reason: '精简模式下必须保留' };
  }
  const rule = group.rules?.[name];
  if (rule?.gpl && config.license !== 'gpl') {
    return { available: false, reason: '仅限 GPL：需要把许可证切换为 GPL' };
  }
  if (rule?.needs && !config.toggles[rule.needs]) {
    return { available: false, reason: `需要开启 ${toggleById(rule.needs).label}` };
  }
  if (rule?.platforms && context.platform && context.platform !== 'all' && !rule.platforms.includes(context.platform)) {
    return { available: false, reason: rule.reason };
  }
  return { available: true };
}

export function requiresGpl(groupId, name) {
  return Boolean(componentGroup(groupId).rules?.[name]?.gpl);
}

// Components that will actually be enabled: locked ones plus the available part of the
// stored selection. The stored selection is kept, so lifting a restriction restores it.
export function effectiveComponents(config, context, groupId) {
  const group = componentGroup(groupId);
  const selected = new Set([...(group.locked || []), ...(config.components[groupId] || [])]);
  return group.items.filter((name) => selected.has(name) && componentStatus(config, context, groupId, name).available);
}

// Turn a toggle on or off and propagate dependencies; returns the ids that changed.
export function setToggle(config, id, value) {
  const toggles = { ...config.toggles };
  const changed = [];
  const visit = (itemId, next) => {
    if (toggles[itemId] === next) return;
    toggles[itemId] = next;
    changed.push(itemId);
    if (next) {
      (toggleById(itemId).requires || []).forEach((dep) => visit(dep, true));
    } else {
      TOGGLES.filter((item) => item.requires?.includes(itemId)).forEach((item) => visit(item.id, false));
    }
  };
  visit(id, value);
  return { config: { ...config, toggles }, changed };
}

// ── Flag generation ──────────────────────────────────────────────────────────

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

export function mergeTokens(tokens) {
  const merged = new Map();
  tokens.forEach((token) => {
    const key = tokenKey(token);
    merged.delete(key);
    merged.set(key, token);
  });
  return [...merged.values()];
}

// Order: segments → toggles → components → custom; later tokens override earlier ones.
export function buildConfigure(config, context = {}) {
  const tokens = mergeTokens([
    ...SEGMENTS.flatMap((segment) => segment.options.find((option) => option.id === config[segment.id])?.flags || []),
    ...TOGGLES.flatMap((item) => (config.toggles[item.id] ? item.on : item.off) || []),
    ...(config.componentMode === 'slim'
      ? ['--disable-everything', ...COMPONENT_GROUPS
        .map((group) => [group, effectiveComponents(config, context, group.id)])
        .filter(([, names]) => names.length)
        .map(([group, names]) => `--enable-${group.id}=${names.join(',')}`)]
      : []),
    ...splitTokens(config.custom),
  ]);

  const notes = [];
  if (!config.toggles.ffmpeg && !config.toggles.ffprobe) notes.push('未选择任何程序，将只生成库和头文件。');
  if (config.componentMode === 'slim'
    && !effectiveComponents(config, context, 'decoder').length && !effectiveComponents(config, context, 'encoder').length) {
    notes.push('未选择任何编解码器，只能做封装格式转换。');
  }
  return { options: tokens.join(' '), tokens, notes };
}
