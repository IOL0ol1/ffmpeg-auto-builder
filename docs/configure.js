// Visual model of FFmpeg configure options. Display texts live in i18n.js, keyed by the
// ids used here (segment.*, option.*, toggleGroup.*, toggle.*, component.*, reason.*, note.*).
// Build targets and what each can build come from targets.json, shared with the workflow.
// Invalid combinations are made unselectable in the UI (disabled options, linked
// dependencies) instead of being validated after the fact.
import TARGETS from './targets.json' with { type: 'json' };

export const PLATFORMS = TARGETS.platforms;

// ── Targets ──────────────────────────────────────────────────────────────────

// context: { platform, archs, packageFormat } — the selected target and package format.
// archs holds one architecture, or several for the multi-target formats; the XCFramework
// pseudo platform "apple" takes "<platform>_<arch>" targets of every Apple platform.

// Formats that combine several architectures (or targets) into one package.
export const MULTI_FORMATS = new Set(['nuget', 'aar', 'xcframework']);
export const XCFRAMEWORK_PLATFORM = 'apple';
const XCFRAMEWORK_PLATFORMS = Object.keys(PLATFORMS).filter((id) => PLATFORMS[id].xcframework);

// Platforms offered for a package format, as [id, label].
export function platformChoices(packageFormat) {
  if (packageFormat === 'xcframework') {
    return [[XCFRAMEWORK_PLATFORM, `Apple (${XCFRAMEWORK_PLATFORMS.map((id) => PLATFORMS[id].label).join(' / ')})`]];
  }
  return Object.entries(PLATFORMS).map(([id, spec]) => [id, spec.label]);
}

// NuGet and AAR packages need shared libraries; AAR is Android only.
export function platformStatus(platform, packageFormat) {
  const linkage = PLATFORMS[platform]?.linkage;
  if (packageFormat === 'aar' && platform !== 'android') return { available: false, reason: 'aarPlatform' };
  if (packageFormat === 'nuget' && linkage && !linkage.includes('shared')) return { available: false, reason: 'nugetPlatform' };
  return { available: true };
}

// Architectures (or XCFramework targets) offered for a platform. Merged architectures
// (universal) are not offered for the multi-target formats, which keep them separate.
export function archChoices(platform, packageFormat) {
  if (platform === XCFRAMEWORK_PLATFORM) {
    return XCFRAMEWORK_PLATFORMS.flatMap((id) => Object.entries(PLATFORMS[id].archs)
      .filter(([, spec]) => !spec.merge)
      .map(([arch, spec]) => ({ id: `${id}_${arch}`, label: `${PLATFORMS[id].label} · ${spec.label}` })));
  }
  return Object.entries(PLATFORMS[platform]?.archs || {})
    .filter(([, spec]) => !(MULTI_FORMATS.has(packageFormat) && spec.merge))
    .map(([id, spec]) => ({ id, label: spec.label }));
}

// [{ platform, spec }] of the selected targets; a merged architecture counts as its parts.
function selectedTargets(context) {
  const pairs = context.platform === XCFRAMEWORK_PLATFORM
    ? (context.archs || []).map((id) => [id.split('_')[0], id.slice(id.indexOf('_') + 1)])
    : (context.archs || []).map((arch) => [context.platform, arch]);
  return pairs.flatMap(([platform, arch]) => {
    const archs = PLATFORMS[platform]?.archs || {};
    return (archs[arch]?.merge || [arch]).filter((id) => archs[id]).map((id) => ({ platform, spec: archs[id] }));
  });
}

// True when every selected target's platform passes the check (and there is one).
function everyPlatform(context, check) {
  const targets = selectedTargets(context);
  const platforms = targets.length ? targets.map((target) => target.platform) : [context.platform];
  return platforms.every((platform) => PLATFORMS[platform] && check(PLATFORMS[platform]));
}

// Mutually exclusive choices, rendered as segmented controls.
export const SEGMENTS = [
  {
    id: 'buildType',
    default: 'release',
    options: [
      { id: 'release', flags: ['--disable-debug'] },
      { id: 'relwithdebinfo', flags: ['--disable-stripping'] },
      { id: 'debug', flags: ['--enable-debug=3', '--disable-optimizations', '--disable-stripping'] },
    ],
  },
  {
    id: 'linkage',
    default: 'static',
    options: [
      // NuGet packages carry shared libraries only (P/Invoke and MSVC import libraries need them).
      { id: 'static', flags: ['--enable-static', '--disable-shared'], excludedFormats: { nuget: 'nugetShared', aar: 'aarShared' } },
      { id: 'shared', flags: ['--enable-shared', '--disable-static'] },
      // An XCFramework holds either static libraries or frameworks.
      { id: 'both', flags: ['--enable-static', '--enable-shared'], excludedFormats: { nuget: 'nugetShared', aar: 'aarShared', xcframework: 'xcframeworkBoth' } },
    ],
  },
  {
    // Not a configure flag: how the third-party libraries (deps/*.sh) are built and linked.
    // It is sent to the workflow as its own parameter (deps_linkage).
    id: 'depsLinkage',
    param: true,
    default: 'static',
    options: [
      { id: 'static', flags: [] },
      { id: 'shared', flags: [] },
    ],
  },
  {
    // No built-in component requires version3; it only matters for third-party libraries,
    // so GPL v3 is not offered (--enable-version3 can still be added as a custom flag).
    id: 'license',
    default: 'gpl',
    options: [
      { id: 'lgpl', flags: [] },
      { id: 'gpl', flags: ['--enable-gpl'] },
    ],
  },
];

// On/off switches. `on` / `off` are the flags emitted for each state;
// `requires` lists toggles that must stay enabled while this one is enabled; `program`
// marks the executables, which some targets cannot build. Libraries a target cannot build
// are listed as "unavailable" in targets.json.

export const TOGGLE_GROUPS = [
  {
    id: 'programs',
    items: [
      { id: 'ffmpeg', default: true, off: ['--disable-ffmpeg'], requires: ['avfilter'], program: true },
      { id: 'ffprobe', default: true, off: ['--disable-ffprobe'], program: true },
      { id: 'avdevice', default: true, off: ['--disable-avdevice'] },
      { id: 'avfilter', default: true, off: ['--disable-avfilter'] },
      { id: 'swscale', default: true, off: ['--disable-swscale'] },
      { id: 'swresample', default: true, off: ['--disable-swresample'] },
      { id: 'doc', default: false, off: ['--disable-doc'] },
    ],
  },
  {
    id: 'features',
    items: [
      { id: 'asm', default: true, off: ['--disable-asm'] },
      { id: 'hwaccel', default: true, off: ['--disable-hwaccels'] },
      { id: 'network', default: true, off: ['--disable-network'] },
      { id: 'autodetect', default: true, off: ['--disable-autodetect'] },
      { id: 'small', default: false, on: ['--enable-small'] },
      { id: 'pic', default: false, on: ['--enable-pic'] },
    ],
  },
  {
    // Built from source by deps/*.sh for every target and linked statically
    // (see scripts/build-deps.sh).
    id: 'libraries',
    items: [
      { id: 'x264', default: true, on: ['--enable-libx264'], gpl: true },
      { id: 'x265', default: true, on: ['--enable-libx265'], gpl: true },
      { id: 'libvpx', default: true, on: ['--enable-libvpx'] },
      { id: 'dav1d', default: true, on: ['--enable-libdav1d'] },
      { id: 'svtav1', default: true, on: ['--enable-libsvtav1'] },
      { id: 'aom', default: true, on: ['--enable-libaom'] },
      { id: 'opus', default: true, on: ['--enable-libopus'] },
      { id: 'mp3lame', default: true, on: ['--enable-libmp3lame'] },
      { id: 'vorbis', default: true, on: ['--enable-libvorbis'] },
      { id: 'webp', default: true, on: ['--enable-libwebp'] },
      { id: 'zimg', default: true, on: ['--enable-libzimg'] },
      { id: 'soxr', default: true, on: ['--enable-libsoxr'] },
      {
        id: 'libass',
        default: true,
        on: ['--enable-libass', '--enable-libfreetype', '--enable-libharfbuzz', '--enable-libfribidi'],
      },
    ],
  },
];

const TOGGLES = TOGGLE_GROUPS.flatMap((group) => group.items);
const toggleById = (id) => TOGGLES.find((item) => item.id === id);

// Component whitelists used in "slim" mode (--disable-everything + --enable-<kind>=...).
// `locked` items are always included in slim mode; `rules` make items unavailable:
//   gpl: needs the GPL license; needs: needs a library toggle; tls: needs a TLS library,
//   which targets.json marks per platform.
export const COMPONENT_GROUPS = [
  {
    id: 'decoder',
    items: ['h264', 'hevc', 'vp8', 'vp9', 'mpeg4', 'mpeg2video', 'mjpeg', 'png', 'gif', 'aac', 'mp3', 'opus', 'vorbis', 'flac', 'alac', 'ac3', 'pcm_s16le'],
    defaults: ['h264', 'hevc', 'vp9', 'aac', 'mp3', 'opus', 'flac', 'pcm_s16le'],
  },
  {
    id: 'encoder',
    items: ['mpeg4', 'mjpeg', 'png', 'gif', 'ffv1', 'aac', 'flac', 'ac3', 'opus', 'pcm_s16le'],
    defaults: ['aac', 'pcm_s16le'],
  },
  {
    id: 'demuxer',
    items: ['mov', 'matroska', 'mpegts', 'flv', 'avi', 'mp3', 'aac', 'ogg', 'flac', 'wav', 'hls', 'image2', 'gif', 'concat'],
    defaults: ['mov', 'matroska', 'mpegts', 'mp3', 'aac', 'ogg', 'flac', 'wav'],
  },
  {
    id: 'muxer',
    items: ['mp4', 'mov', 'matroska', 'webm', 'mpegts', 'flv', 'hls', 'segment', 'mp3', 'adts', 'ogg', 'flac', 'wav', 'image2', 'gif'],
    defaults: ['mp4', 'matroska', 'mpegts', 'adts', 'wav'],
  },
  {
    id: 'parser',
    items: ['h264', 'hevc', 'vp8', 'vp9', 'av1', 'mpeg4video', 'mjpeg', 'png', 'aac', 'mpegaudio', 'opus', 'vorbis', 'flac', 'ac3'],
    defaults: ['h264', 'hevc', 'vp9', 'aac', 'mpegaudio', 'opus', 'flac'],
  },
  {
    id: 'bsf',
    items: ['h264_mp4toannexb', 'hevc_mp4toannexb', 'aac_adtstoasc', 'extract_extradata', 'vp9_superframe'],
    defaults: ['h264_mp4toannexb', 'hevc_mp4toannexb', 'aac_adtstoasc'],
  },
  {
    id: 'protocol',
    items: ['file', 'pipe', 'data', 'concat', 'crypto', 'http', 'https', 'tcp', 'udp', 'rtmp', 'hls'],
    defaults: ['file', 'pipe'],
    locked: ['file'],
    rules: {
      https: { tls: true, reason: 'tls' },
    },
  },
  {
    id: 'filter',
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

export function segmentOptionStatus(context, segmentId, optionId) {
  const option = SEGMENTS.find((segment) => segment.id === segmentId).options.find((item) => item.id === optionId);
  const excluded = option?.excludedFormats?.[context.packageFormat];
  if (excluded) return { available: false, reason: excluded };
  // Platforms limited to static libraries can still have shared ones as XCFramework frameworks.
  if (segmentId === 'linkage' && context.packageFormat !== 'xcframework'
    && !everyPlatform(context, (spec) => !spec.linkage || spec.linkage.includes(optionId))) {
    return { available: false, reason: 'targetLinkage' };
  }
  // Shared third-party libraries need a target that can load shared libraries.
  if (segmentId === 'depsLinkage' && optionId === 'shared' && !segmentOptionStatus(context, 'linkage', 'shared').available) {
    return { available: false, reason: 'targetLinkage' };
  }
  return { available: true };
}

// The stored choice when it is available, otherwise the first available option. The stored
// choice is kept, so it comes back when the restriction is lifted.
export function effectiveSegmentValue(config, context, segmentId) {
  const segment = SEGMENTS.find((item) => item.id === segmentId);
  if (segmentOptionStatus(context, segmentId, config[segmentId]).available) return config[segmentId];
  return segment.options.find((option) => segmentOptionStatus(context, segmentId, option.id).available)?.id ?? config[segmentId];
}

// `reason` is a code translated by the page as reason.<code>.
export function componentStatus(config, context, groupId, name) {
  const group = componentGroup(groupId);
  if (group.locked?.includes(name)) {
    return { available: true, locked: true, reason: 'locked' };
  }
  const rule = group.rules?.[name];
  if (rule?.gpl && config.license !== 'gpl') {
    return { available: false, reason: 'gpl' };
  }
  if (rule?.needs && !config.toggles[rule.needs]) {
    return { available: false, reason: 'needs', needs: rule.needs };
  }
  if (rule?.tls && !everyPlatform(context, (spec) => spec.tls !== false)) {
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

// `reason` is translated as reason.<code>. With several architectures (NuGet) a library
// must be available on each of them.
export function toggleStatus(config, context, id) {
  const item = toggleById(id);
  if (item.program && !everyPlatform(context, (spec) => spec.programs !== false)) return { available: false, reason: 'targetPrograms' };
  if (selectedTargets(context).some(({ spec }) => spec.unavailable?.includes(id))) return { available: false, reason: 'target' };
  if (item.gpl && config.license !== 'gpl') return { available: false, reason: 'gpl' };
  return { available: true };
}

// An unavailable toggle counts as off; the stored choice comes back once it is available.
export function effectiveToggle(config, context, id) {
  return toggleStatus(config, context, id).available && Boolean(config.toggles[id]);
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
    ...SEGMENTS.flatMap((segment) => {
      const value = effectiveSegmentValue(config, context, segment.id);
      return segment.options.find((option) => option.id === value)?.flags || [];
    }),
    ...TOGGLES.flatMap((item) => (effectiveToggle(config, context, item.id) ? item.on : item.off) || []),
    ...(config.componentMode === 'slim'
      ? ['--disable-everything', ...COMPONENT_GROUPS
        .map((group) => [group, effectiveComponents(config, context, group.id)])
        .filter(([, names]) => names.length)
        .map(([group, names]) => `--enable-${group.id}=${names.join(',')}`)]
      : []),
    ...splitTokens(config.custom),
  ]);

  const notes = [];
  if (!effectiveToggle(config, context, 'ffmpeg') && !effectiveToggle(config, context, 'ffprobe')) notes.push('noPrograms');
  if (config.componentMode === 'slim'
    && !effectiveComponents(config, context, 'decoder').length && !effectiveComponents(config, context, 'encoder').length) {
    notes.push('noCodecs');
  }
  return { options: tokens.join(' '), tokens, notes };
}
