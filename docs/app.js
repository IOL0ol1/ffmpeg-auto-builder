import {
  COMPONENT_GROUPS, MULTI_FORMATS, SEGMENTS, TOGGLE_GROUPS,
  archChoices, buildConfigure, componentStatus, defaultConfig, effectiveComponents, effectiveSegmentValue, effectiveToggle,
  normalizeConfig, platformChoices, platformStatus, requiresGpl, sanitizeCustom, segmentOptionStatus, setToggle, toggleStatus,
} from './configure.js';
import {
  LANGUAGES, detectLanguage, getLanguage, setLanguage, t, translateStatic,
} from './i18n.js';

const form = document.querySelector('#build-form');
const langSelect = document.querySelector('#lang-select');
const segmentsNode = document.querySelector('#segments');
const toggleGroupsNode = document.querySelector('#toggle-groups');
const componentModeNode = document.querySelector('#component-mode');
const componentModeHintNode = document.querySelector('#component-mode-hint');
const componentGroupsNode = document.querySelector('#component-groups');
const customOptionsInput = document.querySelector('#custom-options');
const toggleNoticeNode = document.querySelector('#toggle-notice');
const configurePreviewNode = document.querySelector('#configure-preview');
const configNotesNode = document.querySelector('#config-notes');
const copyConfigButton = document.querySelector('#copy-config');
const resetConfigButton = document.querySelector('#reset-config');
const refreshButton = document.querySelector('#refresh-builds');
const detectedRepoNode = document.querySelector('#detected-repo');
const issuesStatusNode = document.querySelector('#issues-status');
const formMessageNode = document.querySelector('#form-message');
const buildListNode = document.querySelector('#build-list');
const targetPlatformSelect = document.querySelector('#target-platform');
const targetArchSelect = document.querySelector('#target-arch');
const targetArchField = document.querySelector('#target-arch-field');
const targetArchMulti = document.querySelector('#target-arch-multi');
const targetArchList = document.querySelector('#target-arch-list');
const packageFormatSelect = document.querySelector('#package-format');
const packageHintNode = document.querySelector('#package-hint');

const BUILD_TITLE_PREFIX = '[build]';
// Unauthenticated GitHub API calls are limited to 60/hour per IP; each refresh costs two.
const AUTO_REFRESH_MS = 10 * 60 * 1000;
const SAFE_REF_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._/-]*$/;
const REPOSITORY_PATTERN = /^(https?:\/\/github\.com\/|git@github\.com:)[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+?(\.git)?\/?$/;
const CONFIG_STORAGE_KEY = 'ffmpeg-builder-config-v2';

// Dynamic content keeps its data (not rendered text) so a language switch can re-render it.
const state = {
  owner: '',
  repo: '',
  refreshHandle: null,
  config: defaultConfig(),
  repoInfo: { status: 'pending' },
  builds: null,
  buildsError: null,
  toggleNotice: null,
  submittedUrl: '',
  formError: null,
};

// ── Repository detection ────────────────────────────────────────────────────

function detectRepository() {
  const { hostname, pathname } = window.location;
  const pathParts = pathname.split('/').filter(Boolean);

  if (hostname.endsWith('.github.io')) {
    return {
      owner: hostname.split('.')[0] || '',
      repo: pathParts[0] || '',
    };
  }

  if (pathParts.length >= 2) {
    return { owner: pathParts[0], repo: pathParts[1] };
  }

  return { owner: '', repo: '' };
}

function repoUrl(path = '') {
  return `https://github.com/${state.owner}/${state.repo}${path}`;
}

// ── GitHub API helper (unauthenticated, public data only) ──────────────────

// Errors carry a translation key so their message follows the page language.
function apiError(key, vars = {}) {
  const error = new Error(key);
  error.i18n = { key, vars };
  return error;
}

function errorText(error) {
  return error.i18n ? t(error.i18n.key, error.i18n.vars) : error.message;
}

async function githubFetch(path) {
  const response = await fetch(`https://api.github.com${path}`, {
    headers: { Accept: 'application/vnd.github+json' },
  });

  if (!response.ok) {
    if (response.status === 403 || response.status === 429) throw apiError('api.rateLimit');
    if (response.status === 404) throw apiError('api.notFound');
    throw apiError('api.failed', { status: response.status });
  }

  return response.json();
}

function makeLink(href, text) {
  const a = document.createElement('a');
  a.href = href;
  a.target = '_blank';
  a.rel = 'noreferrer';
  a.textContent = text;
  return a;
}

async function loadRepositoryInfo() {
  if (!state.owner || !state.repo) {
    state.repoInfo = { status: 'undetected' };
    renderRepositoryInfo();
    return;
  }

  try {
    const repo = await githubFetch(`/repos/${state.owner}/${state.repo}`);
    state.repoInfo = { status: repo.has_issues ? 'enabled' : 'disabled' };
  } catch (error) {
    state.repoInfo = { status: 'error', error };
  }
  renderRepositoryInfo();
}

function renderRepositoryInfo() {
  const { status, error } = state.repoInfo;
  if (status === 'undetected') {
    detectedRepoNode.textContent = t('repo.undetected');
    issuesStatusNode.textContent = t('common.unknown');
    return;
  }

  detectedRepoNode.replaceChildren(makeLink(repoUrl(), `${state.owner}/${state.repo}`));
  if (status === 'pending') {
    issuesStatusNode.textContent = t('common.detecting');
  } else if (status === 'enabled') {
    issuesStatusNode.textContent = t('issues.enabled');
  } else if (status === 'disabled') {
    issuesStatusNode.replaceChildren(
      t('issues.disabled.before'),
      makeLink(repoUrl('/settings'), 'Settings → General → Features'),
      t('issues.disabled.after'),
    );
  } else {
    issuesStatusNode.textContent = errorText(error);
  }
}

// ── Form helpers ────────────────────────────────────────────────────────────

// Platforms and architectures come from targets.json; their labels are technical names.
// Keeps the current platform when the package format still allows it.
function updatePlatformOptions() {
  const current = targetPlatformSelect.value;
  const options = platformChoices(packageFormatSelect.value).map(([id, label]) => {
    const status = platformStatus(id, packageFormatSelect.value);
    const opt = document.createElement('option');
    opt.value = id;
    opt.textContent = label;
    opt.disabled = !status.available;
    opt.title = status.available ? '' : t(`reason.${status.reason}`);
    return opt;
  });
  targetPlatformSelect.replaceChildren(...options);
  const keep = options.find((opt) => opt.value === current && !opt.disabled) || options.find((opt) => !opt.disabled);
  if (keep) targetPlatformSelect.value = keep.value;
}

// Architectures picked per platform for the multi-target formats (NuGet, AAR, XCFramework),
// kept while switching platforms or formats.
const nugetArchs = {};

// One architecture from a select, or several from checkboxes for NuGet / AAR / XCFramework.
// Keeps the current architecture when the new platform / format still offers it.
function updateArchOptions() {
  const platform = targetPlatformSelect.value;
  const nuget = MULTI_FORMATS.has(packageFormatSelect.value);
  const choices = archChoices(platform, packageFormatSelect.value);
  const current = targetArchSelect.value;
  targetArchField.hidden = nuget;
  targetArchMulti.hidden = !nuget;
  if (!nuget) {
    targetArchSelect.replaceChildren(...choices.map(({ id, label }) => {
      const opt = document.createElement('option');
      opt.value = id;
      opt.textContent = label;
      opt.selected = id === current;
      return opt;
    }));
    return;
  }

  const ids = choices.map((choice) => choice.id);
  const picked = (nugetArchs[platform] || [current]).filter((id) => ids.includes(id));
  if (!picked.length && platform === 'apple') picked.push(...ids.filter((id) => id.startsWith('ios_')));
  nugetArchs[platform] = picked.length ? picked : ids.slice(0, 1);
  targetArchList.replaceChildren(...choices.map(({ id, label }) => {
    const chip = makeChip(label, (checked) => {
      const others = nugetArchs[platform].filter((arch) => arch !== id);
      nugetArchs[platform] = checked ? [...others, id] : others;
      syncArchChips();
      syncConfigUI();
    });
    chip.dataset.arch = id;
    return chip;
  }));
  syncArchChips();
}

function syncArchChips() {
  const picked = nugetArchs[targetPlatformSelect.value] || [];
  targetArchList.querySelectorAll('[data-arch]').forEach((chip) => {
    const input = chip.querySelector('input');
    input.checked = picked.includes(chip.dataset.arch);
    // The last selected architecture cannot be cleared.
    const last = input.checked && picked.length === 1;
    input.disabled = last;
    chip.title = last ? t('form.arch.lastOne') : '';
  });
}

// The selected architectures in targets.json order.
function selectedArchs() {
  if (!MULTI_FORMATS.has(packageFormatSelect.value)) return [targetArchSelect.value];
  const picked = nugetArchs[targetPlatformSelect.value] || [];
  return archChoices(targetPlatformSelect.value, packageFormatSelect.value).map((choice) => choice.id).filter((id) => picked.includes(id));
}

// ── configure option builder ────────────────────────────────────────────────

// The controls are rendered from the model in configure.js; every change updates
// state.config and syncConfigUI() reflects it back into the DOM. Invalid choices are made
// unavailable in the controls themselves instead of being validated afterwards.

function configContext() {
  return { platform: targetPlatformSelect.value, archs: selectedArchs(), packageFormat: packageFormatSelect.value };
}

function loadSavedConfig() {
  try {
    return normalizeConfig(JSON.parse(localStorage.getItem(CONFIG_STORAGE_KEY) || 'null'));
  } catch {
    return defaultConfig();
  }
}

function saveConfig() {
  try {
    localStorage.setItem(CONFIG_STORAGE_KEY, JSON.stringify(state.config));
  } catch {
    // Storage may be unavailable (private mode); the page works without it.
  }
}

function makeSegmented(container, options, onSelect) {
  container.replaceChildren(...options.map((option) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.setAttribute('role', 'radio');
    button.dataset.value = option.id;
    button.textContent = option.label;
    if (option.flags) button.title = option.flags.join(' ') || t('config.noFlags');
    button.addEventListener('click', () => onSelect(option.id));
    return button;
  }));
}

function syncSegmented(container, value) {
  container.querySelectorAll('button').forEach((button) => {
    button.setAttribute('aria-checked', String(button.dataset.value === value));
  });
}

function makeChip(text, onChange) {
  const label = document.createElement('label');
  label.className = 'choice';
  const input = document.createElement('input');
  input.type = 'checkbox';
  input.addEventListener('change', () => onChange(input.checked));
  const span = document.createElement('span');
  span.textContent = text;
  label.append(input, span);
  return label;
}

// Briefly highlight controls changed indirectly by a dependency.
function flashControls(keys) {
  keys.forEach((key) => {
    const [kind, id] = key.split(':');
    const node = kind === 'toggle' ? toggleGroupsNode.querySelector(`[data-toggle="${id}"]`) : null;
    if (!node) return;
    node.classList.remove('flash');
    void node.offsetWidth; // restart the animation
    node.classList.add('flash');
  });
}

function setToggleFromUI(item, checked) {
  const result = setToggle(state.config, item.id, checked);
  updateConfig(result.config);
  const others = result.changed.filter((id) => id !== item.id);
  state.toggleNotice = others.length ? { item: item.id, others, checked } : null;
  renderToggleNotice();
  flashControls(others.map((id) => `toggle:${id}`));
}

function renderToggleNotice() {
  const notice = state.toggleNotice;
  toggleNoticeNode.textContent = notice
    ? t(notice.checked ? 'notice.linkedOn' : 'notice.linkedOff', {
      labels: notice.others.map((id) => t(`toggle.${id}`)).join(t('common.listSep')),
      item: t(`toggle.${notice.item}`),
    })
    : '';
}

function renderConfigControls() {
  segmentsNode.replaceChildren(...SEGMENTS.map((segment) => {
    const group = document.createElement('div');
    group.className = 'choice-group';
    const title = document.createElement('span');
    title.className = 'group-title';
    title.textContent = t(`segment.${segment.id}`);
    const control = document.createElement('div');
    control.className = 'segmented';
    control.setAttribute('role', 'radiogroup');
    control.setAttribute('aria-label', t(`segment.${segment.id}`));
    control.dataset.segment = segment.id;
    makeSegmented(
      control,
      segment.options.map((option) => ({ ...option, label: t(`option.${segment.id}.${option.id}`) })),
      (value) => updateConfig({ [segment.id]: value }),
    );
    group.append(title, control);
    return group;
  }));

  toggleGroupsNode.replaceChildren(...TOGGLE_GROUPS.map((group) => {
    const wrapper = document.createElement('div');
    wrapper.className = 'choice-group';
    const title = document.createElement('span');
    title.className = 'group-title';
    title.textContent = t(`toggleGroup.${group.id}`);
    const chips = document.createElement('div');
    chips.className = 'choices chips';
    group.items.forEach((item) => {
      const chip = makeChip(t(`toggle.${item.id}`), (checked) => setToggleFromUI(item, checked));
      chip.dataset.toggle = item.id;
      if (item.gpl) {
        const badge = document.createElement('span');
        badge.className = 'badge';
        badge.textContent = 'GPL';
        chip.appendChild(badge);
      }
      chips.appendChild(chip);
    });
    wrapper.append(title, chips);
    return wrapper;
  }));

  makeSegmented(componentModeNode, [
    { id: 'all', label: t('mode.all') },
    { id: 'slim', label: t('mode.slim') },
  ], (value) => updateConfig({ componentMode: value }));

  // Keep expanded component groups open when re-rendering for a language switch.
  const openGroups = new Set([...componentGroupsNode.querySelectorAll('details[open]')].map((node) => node.dataset.group));
  componentGroupsNode.replaceChildren(...COMPONENT_GROUPS.map((group) => {
    const details = document.createElement('details');
    details.className = 'component-group';
    details.dataset.group = group.id;
    details.open = openGroups.has(group.id);
    const summary = document.createElement('summary');
    const name = document.createElement('span');
    name.textContent = t(`component.${group.id}`);
    const count = document.createElement('span');
    count.className = 'muted count';
    summary.append(name, count);

    const setSelection = (names) => {
      updateConfig({ components: { ...state.config.components, [group.id]: names } });
    };
    const tools = document.createElement('div');
    tools.className = 'component-tools';
    [['tools.all', () => setSelection([...group.items])], ['tools.none', () => setSelection([])], ['tools.defaults', () => setSelection([...group.defaults])]]
      .forEach(([key, action]) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'secondary small';
        button.textContent = t(key);
        button.addEventListener('click', action);
        tools.appendChild(button);
      });

    const chips = document.createElement('div');
    chips.className = 'choices chips';
    group.items.forEach((item) => {
      const chip = makeChip(item, (checked) => {
        const current = state.config.components[group.id] || [];
        // Keep the catalogue order so the generated flag is stable.
        setSelection(group.items.filter((entry) => (entry === item ? checked : current.includes(entry))));
      });
      chip.dataset.component = item;
      if (requiresGpl(group.id, item)) {
        const badge = document.createElement('span');
        badge.className = 'badge';
        badge.textContent = 'GPL';
        chip.appendChild(badge);
      }
      chips.appendChild(chip);
    });

    details.append(summary, tools, chips);
    return details;
  }));
}

function statusReason(status) {
  return status.reason ? t(`reason.${status.reason}`, { lib: status.needs ? t(`toggle.${status.needs}`) : '' }) : '';
}

function syncConfigUI() {
  const { config } = state;
  const context = configContext();

  SEGMENTS.forEach((segment) => {
    const control = segmentsNode.querySelector(`[data-segment="${segment.id}"]`);
    const value = effectiveSegmentValue(config, context, segment.id);
    syncSegmented(control, value);
    control.querySelectorAll('button').forEach((button) => {
      const status = segmentOptionStatus(context, segment.id, button.dataset.value);
      const option = segment.options.find((item) => item.id === button.dataset.value);
      button.disabled = !status.available;
      button.title = status.available
        ? (segment.param ? t(`option.${segment.id}.${option.id}.hint`) : option.flags.join(' ') || t('config.noFlags'))
        : t(`reason.${status.reason}`);
    });
  });
  packageHintNode.textContent = MULTI_FORMATS.has(context.packageFormat) ? t(`form.package.${context.packageFormat}Hint`) : '';

  const toggleItems = TOGGLE_GROUPS.flatMap((group) => group.items);
  toggleGroupsNode.querySelectorAll('[data-toggle]').forEach((chip) => {
    const id = chip.dataset.toggle;
    const item = toggleItems.find((entry) => entry.id === id);
    const status = toggleStatus(config, context, id);
    const input = chip.querySelector('input');
    input.checked = effectiveToggle(config, context, id);
    input.disabled = !status.available;
    chip.classList.toggle('unavailable', !status.available);
    chip.title = status.available
      ? `${t(`toggle.${id}.hint`)}\n${[...(item.on || []), ...(item.off || [])].join(' / ')}`
      : statusReason(status);
  });

  syncSegmented(componentModeNode, config.componentMode);
  const slim = config.componentMode === 'slim';
  componentModeHintNode.textContent = t(slim ? 'mode.slim.hint' : 'mode.all.hint');
  componentGroupsNode.hidden = !slim;
  COMPONENT_GROUPS.forEach((group) => {
    const node = componentGroupsNode.querySelector(`[data-group="${group.id}"]`);
    const selected = effectiveComponents(config, context, group.id);
    node.querySelector('.count').textContent = `${selected.length} / ${group.items.length}`;
    node.querySelectorAll('[data-component]').forEach((chip) => {
      const name = chip.dataset.component;
      const status = componentStatus(config, context, group.id, name);
      const input = chip.querySelector('input');
      input.checked = selected.includes(name);
      input.disabled = !status.available || Boolean(status.locked);
      chip.classList.toggle('unavailable', !status.available);
      chip.classList.toggle('locked', Boolean(status.locked));
      chip.title = statusReason(status) || `--enable-${group.id}=${name}`;
    });
  });

  if (customOptionsInput.value !== config.custom) {
    customOptionsInput.value = config.custom;
  }

  const { options, notes } = buildConfigure(config, context);
  configurePreviewNode.textContent = options;
  configNotesNode.replaceChildren(...notes.map((note) => {
    const li = document.createElement('li');
    li.className = 'muted';
    li.textContent = t(`note.${note}`);
    return li;
  }));
}

function updateConfig(patch) {
  state.config = { ...state.config, ...patch };
  saveConfig();
  syncConfigUI();
}

async function copyConfigure() {
  try {
    await navigator.clipboard.writeText(configurePreviewNode.textContent);
    copyConfigButton.textContent = t('config.copied');
  } catch {
    copyConfigButton.textContent = t('config.copyFailed');
  }
  window.setTimeout(() => { copyConfigButton.textContent = t('config.copy'); }, 1500);
}

// ── Submit ──────────────────────────────────────────────────────────────────

function readForm() {
  const formData = new FormData(form);
  const value = (name) => String(formData.get(name) || '').trim();
  return {
    sourceRepository: value('sourceRepository'),
    sourceRef: value('sourceRef'),
    targetPlatform: value('targetPlatform'),
    targetArch: selectedArchs().join(','),
    packageFormat: value('packageFormat'),
    depsLinkage: effectiveSegmentValue(state.config, configContext(), 'depsLinkage'),
    configureOptions: buildConfigure(state.config, configContext()).options,
  };
}

// Mirrors scripts/resolve-params.sh so mistakes are caught before leaving the page.
function validate(params) {
  if (!REPOSITORY_PATTERN.test(params.sourceRepository)) return 'validate.repo';
  if (params.sourceRef && !SAFE_REF_PATTERN.test(params.sourceRef)) return 'validate.ref';
  return '';
}

// The issue template follows the page language; the workflow replies in the same language.
function buildIssueUrl(params) {
  const title = `${BUILD_TITLE_PREFIX} ${params.targetPlatform}/${params.targetArch} ${params.sourceRef || 'HEAD'}`;
  const query = new URLSearchParams({
    template: getLanguage().issueTemplate,
    title,
    source_repository: params.sourceRepository,
    source_ref: params.sourceRef,
    target_platform: params.targetPlatform,
    target_arch: params.targetArch,
    package_format: params.packageFormat,
    deps_linkage: params.depsLinkage,
    configure_options: params.configureOptions,
  });
  return repoUrl(`/issues/new?${query}`);
}

function renderFormMessage() {
  formMessageNode.className = 'form-message';
  if (state.formError) {
    formMessageNode.classList.add('status-error');
    formMessageNode.textContent = t(state.formError);
  } else if (state.submittedUrl) {
    formMessageNode.classList.add('status-warn');
    formMessageNode.replaceChildren(
      t('submit.opened.before'),
      makeLink(state.submittedUrl, t('submit.opened.link')),
      t('submit.opened.after'),
    );
  } else {
    formMessageNode.textContent = '';
  }
}

function handleSubmit(event) {
  event.preventDefault();
  state.submittedUrl = '';
  state.formError = null;

  if (!state.owner || !state.repo) {
    state.formError = 'form.repoUnknown';
  } else {
    const params = readForm();
    state.formError = validate(params) || null;
    if (!state.formError) {
      state.submittedUrl = buildIssueUrl(params);
      window.open(state.submittedUrl, '_blank', 'noopener');
    }
  }
  renderFormMessage();
}

// ── Build records ───────────────────────────────────────────────────────────

function runStatusLabel(run) {
  if (!run) return t('run.waiting');
  if (run.status !== 'completed') return t(run.status === 'queued' ? 'run.queued' : 'run.running');
  if (run.conclusion === 'success') return t('run.success');
  if (run.conclusion === 'skipped') return t('run.skipped');
  return t('run.ended', { conclusion: run.conclusion || 'unknown' });
}

function statusClass(run) {
  if (!run || run.status !== 'completed') return 'status-warn';
  if (run.conclusion === 'success') return 'status-ok';
  return run.conclusion === 'skipped' ? '' : 'status-error';
}

function stepIcon(status, conclusion) {
  if (status !== 'completed') return '⏳';
  if (conclusion === 'success') return '✅';
  if (conclusion === 'skipped') return '⏭';
  return '❌';
}

function formatDuration(startedAt, completedAt) {
  if (!startedAt || !completedAt) return '';
  const secs = Math.round((new Date(completedAt) - new Date(startedAt)) / 1000);
  if (secs < 60) return `${secs}s`;
  return `${Math.floor(secs / 60)}m ${secs % 60}s`;
}

function renderJobsSummary(jobs) {
  const wrapper = document.createElement('div');
  wrapper.className = 'jobs-summary';

  jobs.forEach((job) => {
    const details = document.createElement('details');
    details.className = `job-entry ${statusClass(job)}`;

    const dur = formatDuration(job.started_at, job.completed_at);
    const summary = document.createElement('summary');
    summary.textContent = `${stepIcon(job.status, job.conclusion)} ${job.name}${dur ? ` (${dur})` : ''}`;
    details.appendChild(summary);

    const steps = (job.steps || []).filter((s) => s.name !== 'Set up job' && s.name !== 'Complete job');
    if (steps.length) {
      const list = document.createElement('ul');
      list.className = 'step-list';
      steps.forEach((step) => {
        const li = document.createElement('li');
        const stepDur = formatDuration(step.started_at, step.completed_at);
        li.textContent = `${stepIcon(step.status, step.conclusion)} ${step.name}${stepDur ? ` (${stepDur})` : ''}`;
        list.appendChild(li);
      });
      details.appendChild(list);
    }

    wrapper.appendChild(details);
  });

  return wrapper;
}

function attachLogViewerButton(card, runId) {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'secondary log-btn';
  btn.textContent = t('log.expand');

  let summaryNode = null;
  btn.addEventListener('click', async () => {
    if (summaryNode) {
      summaryNode.hidden = !summaryNode.hidden;
      btn.textContent = t(summaryNode.hidden ? 'log.expand' : 'log.collapse');
      return;
    }

    btn.textContent = t('common.loading');
    btn.disabled = true;
    try {
      const payload = await githubFetch(`/repos/${state.owner}/${state.repo}/actions/runs/${runId}/jobs`);
      summaryNode = renderJobsSummary(payload.jobs || []);
      card.appendChild(summaryNode);
      btn.textContent = t('log.collapse');
    } catch (err) {
      btn.textContent = t('log.failed', { error: errorText(err) });
    } finally {
      btn.disabled = false;
    }
  });

  return btn;
}

function buildCard(issue, run) {
  const card = document.createElement('article');
  card.className = `run-card ${statusClass(run)}`;

  const header = document.createElement('header');
  const heading = document.createElement('h3');
  heading.textContent = `#${issue.number} · ${runStatusLabel(run)}`;
  const time = document.createElement('span');
  time.textContent = new Date(issue.created_at).toLocaleString(getLanguage().id);
  header.append(heading, time);
  card.appendChild(header);

  const titleP = document.createElement('p');
  titleP.textContent = issue.title;
  card.appendChild(titleP);

  const metaP = document.createElement('p');
  metaP.className = 'muted';
  metaP.textContent = t('card.meta', {
    user: issue.user?.login || 'unknown',
    state: t(issue.state === 'open' ? 'card.open' : 'card.closed'),
  });
  card.appendChild(metaP);

  const linksP = document.createElement('p');
  linksP.append(makeLink(issue.html_url, t('card.issueLink')));
  if (run) {
    linksP.append(' · ', makeLink(run.html_url, t('card.runLink')));
  }
  card.appendChild(linksP);

  if (run) {
    card.appendChild(attachLogViewerButton(card, run.id));
  }

  return card;
}

function renderBuilds() {
  buildListNode.className = 'run-list';
  if (state.buildsError) {
    buildListNode.classList.add('empty', 'status-error');
    buildListNode.textContent = errorText(state.buildsError);
    return;
  }
  if (!state.builds) {
    buildListNode.classList.add('empty');
    buildListNode.textContent = t('common.loading');
    return;
  }
  if (!state.builds.issues.length) {
    buildListNode.classList.add('empty');
    buildListNode.textContent = t('builds.empty');
    return;
  }
  buildListNode.replaceChildren(...state.builds.issues.map((issue) => buildCard(issue, state.builds.runsByIssue.get(issue.number))));
}

async function refreshBuilds() {
  if (state.refreshHandle) {
    window.clearTimeout(state.refreshHandle);
    state.refreshHandle = null;
  }
  if (!state.owner || !state.repo) {
    return;
  }

  refreshButton.disabled = true;
  try {
    const [issues, runsPayload] = await Promise.all([
      githubFetch(`/repos/${state.owner}/${state.repo}/issues?state=all&sort=created&direction=desc&per_page=50`),
      githubFetch(`/repos/${state.owner}/${state.repo}/actions/workflows/build.yml/runs?event=issues&per_page=50`),
    ]);

    // Run titles look like "#12 [build] linux/x86_64 n7.1" (see run-name in build.yml).
    const runsByIssue = new Map();
    (runsPayload.workflow_runs || []).forEach((run) => {
      const match = (run.display_title || '').match(/^#(\d+) /);
      if (match && !runsByIssue.has(Number(match[1]))) {
        runsByIssue.set(Number(match[1]), run);
      }
    });

    const builds = (issues || [])
      .filter((issue) => !issue.pull_request && issue.title.startsWith(BUILD_TITLE_PREFIX))
      .slice(0, 20);
    state.builds = { issues: builds, runsByIssue };
    state.buildsError = null;

    const inProgress = builds.some((issue) => {
      const run = runsByIssue.get(issue.number);
      return issue.state === 'open' && (!run || run.status !== 'completed');
    });
    if (inProgress) {
      state.refreshHandle = window.setTimeout(refreshBuilds, AUTO_REFRESH_MS);
    }
  } catch (error) {
    state.buildsError = error;
  } finally {
    refreshButton.disabled = false;
  }
  renderBuilds();
}

// ── Language ────────────────────────────────────────────────────────────────

function applyLanguage(id) {
  setLanguage(id);
  langSelect.value = getLanguage().id;
  translateStatic();
  updatePlatformOptions();
  updateArchOptions();
  renderConfigControls();
  syncConfigUI();
  renderToggleNotice();
  renderRepositoryInfo();
  renderFormMessage();
  renderBuilds();
}

// ── Init ────────────────────────────────────────────────────────────────────

Object.assign(state, detectRepository());

langSelect.replaceChildren(...LANGUAGES.map((language) => {
  const opt = document.createElement('option');
  opt.value = language.id;
  opt.textContent = language.label;
  return opt;
}));
langSelect.addEventListener('change', () => applyLanguage(langSelect.value));

targetPlatformSelect.addEventListener('change', () => {
  updateArchOptions();
  syncConfigUI(); // platform-specific components (e.g. https) may change availability
});
packageFormatSelect.addEventListener('change', () => {
  updatePlatformOptions(); // NuGet / AAR need shared libraries, XCFramework has its own platform
  updateArchOptions(); // the multi-target formats pick several architectures, without merged ones
  syncConfigUI(); // NuGet / AAR allow shared linking only, XCFramework not both
});
targetArchSelect.addEventListener('change', syncConfigUI); // third-party libraries depend on the target

state.config = loadSavedConfig();
applyLanguage(detectLanguage());

customOptionsInput.addEventListener('input', () => {
  const clean = sanitizeCustom(customOptionsInput.value);
  if (clean !== customOptionsInput.value) {
    // Drop disallowed characters as they are typed, keeping the caret in place.
    const caret = customOptionsInput.selectionStart - (customOptionsInput.value.length - clean.length);
    customOptionsInput.value = clean;
    customOptionsInput.setSelectionRange(caret, caret);
  }
  updateConfig({ custom: clean });
});
copyConfigButton.addEventListener('click', copyConfigure);
resetConfigButton.addEventListener('click', () => {
  state.config = defaultConfig();
  state.toggleNotice = null;
  saveConfig();
  syncConfigUI();
  renderToggleNotice();
});

form.addEventListener('submit', handleSubmit);
refreshButton.addEventListener('click', refreshBuilds);

loadRepositoryInfo();
refreshBuilds();
