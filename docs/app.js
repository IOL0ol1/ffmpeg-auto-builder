const form = document.querySelector('#build-form');
const applyPresetButton = document.querySelector('#apply-preset');
const refreshRunsButton = document.querySelector('#refresh-runs');
const detectedRepoNode = document.querySelector('#detected-repo');
const defaultBranchNode = document.querySelector('#default-branch');
const taskStatusNode = document.querySelector('#task-status');
const runListNode = document.querySelector('#run-list');
const historyListNode = document.querySelector('#history-list');
const linkTemplate = document.querySelector('#link-template');

const HISTORY_KEY = 'ffmpeg-build-history-v1';
const HISTORY_MAX = 30;
const POLL_INTERVAL_MS = 10000;
const POLL_MAX_FAILURES = 5;

const state = {
  owner: '',
  repo: '',
  defaultBranch: '',
  token: '',
  releaseTag: '',
  runId: null,
  currentUser: '',
  canPush: false,
  pollHandle: null,
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

function updateDetectedRepo() {
  const { owner, repo } = detectRepository();
  state.owner = owner;
  state.repo = repo;
  detectedRepoNode.textContent = owner && repo ? `${owner}/${repo}` : '无法自动识别，请确认 Pages 以仓库路径形式访问';
}

// ── Local history (no PAT stored) ──────────────────────────────────────────

function loadHistory() {
  try {
    return JSON.parse(localStorage.getItem(HISTORY_KEY) || '[]');
  } catch {
    return [];
  }
}

function saveHistory(entries) {
  try {
    localStorage.setItem(HISTORY_KEY, JSON.stringify(entries.slice(0, HISTORY_MAX)));
  } catch {
    // Ignore quota errors
  }
}

function upsertHistoryEntry(entry) {
  const entries = loadHistory();
  const idx = entries.findIndex((e) => e.runId === entry.runId);
  if (idx >= 0) {
    entries[idx] = { ...entries[idx], ...entry };
  } else {
    entries.unshift(entry);
  }
  saveHistory(entries);
}

// ── GitHub API helper ───────────────────────────────────────────────────────

function setMessage(node, type, message) {
  node.className = type ? `${node.id === 'task-status' ? 'status-panel' : 'run-list'} ${type}` : node.className;
  node.textContent = message;
}

async function githubFetch(path, token, options = {}) {
  const authHeader = token ? ['Bearer', token].join(' ') : '';
  const response = await fetch(`https://api.github.com${path}`, {
    ...options,
    headers: {
      Accept: 'application/vnd.github+json',
      ...(token ? { Authorization: authHeader } : {}),
      ...(options.headers || {}),
    },
  });

  if (!response.ok && response.status !== 204) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(payload.message || `GitHub API 请求失败: ${response.status}`);
  }

  return response.status === 204 ? null : response.json();
}

async function ensureRepositoryMetadata(token) {
  if (!state.owner || !state.repo) {
    throw new Error('当前页面无法识别出 Fork 仓库，请检查 GitHub Pages 访问地址。');
  }

  const repo = await githubFetch(`/repos/${state.owner}/${state.repo}`, token);
  state.defaultBranch = repo.default_branch;
  state.canPush = Boolean(repo.permissions?.push);
  defaultBranchNode.textContent = repo.default_branch;
}

async function ensureWriteAccess(token) {
  const user = await githubFetch('/user', token);
  state.currentUser = user.login;
  if (!state.canPush) {
    throw new Error(`当前 PAT 所属账号 ${user.login} 对 ${state.owner}/${state.repo} 没有写权限，无法触发工作流。`);
  }
}

// ── Log viewer (jobs + steps summary) ──────────────────────────────────────

async function loadRunJobs(runId, token) {
  const payload = await githubFetch(
    `/repos/${state.owner}/${state.repo}/actions/runs/${runId}/jobs`,
    token,
  );
  return payload.jobs || [];
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

  // Skip the "setup" job (just a matrix helper) unless it failed
  const displayJobs = jobs.filter((j) => j.name !== 'setup' || j.conclusion !== 'success');

  displayJobs.forEach((job) => {
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

function attachLogViewerButton(container, runId, linkEl) {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'secondary log-btn';
  btn.textContent = '展开日志摘要';

  let loaded = false;
  btn.addEventListener('click', async () => {
    if (loaded) {
      const existing = container.querySelector('.jobs-summary');
      if (existing) {
        existing.hidden = !existing.hidden;
        btn.textContent = existing.hidden ? '展开日志摘要' : '收起日志摘要';
      }
      return;
    }

    const token = document.querySelector('#pat').value.trim();
    if (!token) {
      btn.textContent = '请先填写 PAT';
      return;
    }

    btn.textContent = '加载中…';
    btn.disabled = true;
    try {
      const jobs = await loadRunJobs(runId, token);
      const summary = renderJobsSummary(jobs);
      linkEl.insertAdjacentElement('afterend', summary);
      loaded = true;
      btn.textContent = '收起日志摘要';
      btn.disabled = false;
    } catch (err) {
      btn.textContent = `加载失败: ${err.message}`;
      btn.disabled = false;
    }
  });

  return btn;
}

// ── Preset / form helpers ───────────────────────────────────────────────────

function normalizeConfigurePreset() {
  const preset = document.querySelector('#preset').value.trim();
  if (!preset) {
    return;
  }

  const textarea = document.querySelector('#configure-options');
  const existing = textarea.value.trim();
  const nextValue = [existing, preset].filter(Boolean).join('\n');
  textarea.value = nextValue;
}

function makeReleaseTag(targetPlatform, targetArch) {
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '').toLowerCase();
  const suffix = Math.random().toString(36).slice(2, 6);
  return `ffmpeg-${targetPlatform}-${targetArch}-${stamp}-${suffix}`;
}

function extractReleaseTag(run) {
  const title = run.display_title || '';
  const match = title.match(/(ffmpeg-\w+-\w+-\d{8}t\d{6}-[a-z0-9]{4})/i);
  return match ? match[1] : '';
}

function statusLabel(run) {
  if (run.status === 'completed') {
    if (run.conclusion === 'success') {
      return '已成功';
    }
    return `已结束（${run.conclusion || 'unknown'}）`;
  }

  return run.status === 'queued' ? '排队中' : '执行中';
}

function statusClass(run) {
  if (run.status !== 'completed') {
    return 'status-warn';
  }

  return run.conclusion === 'success' ? 'status-ok' : 'status-error';
}

function buildList(items) {
  if (!items.length) {
    return document.createTextNode('暂无可展示的链接。');
  }

  const fragment = document.createElement('ul');
  fragment.className = 'links';

  items.forEach((item) => {
    const node = linkTemplate.content.firstElementChild.cloneNode(true);
    const anchor = node.querySelector('a');
    anchor.href = item.href;
    anchor.textContent = item.label;
    fragment.appendChild(node);
  });

  return fragment;
}

// ── Run data loaders ────────────────────────────────────────────────────────

async function findReleaseByTag(releaseTag, token) {
  // GET /releases/tags/{tag} only returns published releases, so search the list for drafts.
  const releases = await githubFetch(`/repos/${state.owner}/${state.repo}/releases?per_page=50`, token);
  return (releases || []).find((release) => release.tag_name === releaseTag) || null;
}

async function loadRunDownloads(runId, releaseTag, token) {
  const [artifactsPayload, releasePayload] = await Promise.all([
    githubFetch(`/repos/${state.owner}/${state.repo}/actions/runs/${runId}/artifacts`, token),
    releaseTag ? findReleaseByTag(releaseTag, token).catch(() => null) : Promise.resolve(null),
  ]);

  const items = [
    ...(artifactsPayload?.artifacts || [])
      .filter((artifact) => !artifact.name.startsWith('slice-'))
      .map((artifact) => ({
        label: `Artifact：${artifact.name}`,
        // Browser-friendly page; archive_download_url requires an Authorization header.
        href: `https://github.com/${state.owner}/${state.repo}/actions/runs/${runId}/artifacts/${artifact.id}`,
      })),
  ];

  if (releasePayload?.html_url) {
    items.push({
      label: `Draft Release：${releasePayload.name || releasePayload.tag_name}`,
      href: releasePayload.html_url,
    });

    (releasePayload.assets || []).forEach((asset) => {
      items.push({
        label: `Release 资源：${asset.name}`,
        href: asset.browser_download_url,
      });
    });
  }

  return items;
}

// ── Render helpers ──────────────────────────────────────────────────────────

function renderTaskStatus(run, links = []) {
  taskStatusNode.className = `status-panel ${statusClass(run)}`;
  taskStatusNode.innerHTML = '';

  const summary = document.createElement('div');
  const headline = document.createElement('p');
  const strong = document.createElement('strong');
  strong.textContent = `Run #${run.run_number}`;
  headline.append(strong, `：${statusLabel(run)}`);
  const platformLine = document.createElement('p');
  platformLine.textContent = `平台：${run.display_title || run.name}`;
  summary.append(headline, platformLine);

  const actionLink = document.createElement('p');
  const a = document.createElement('a');
  a.href = run.html_url;
  a.target = '_blank';
  a.rel = 'noreferrer';
  a.textContent = '查看 Actions 日志';
  actionLink.appendChild(a);
  summary.appendChild(actionLink);

  taskStatusNode.appendChild(summary);
  taskStatusNode.appendChild(buildList(links));
  taskStatusNode.appendChild(attachLogViewerButton(taskStatusNode, run.id, taskStatusNode.lastChild));
}

function buildRunCard(run, fromHistory = false) {
  const card = document.createElement('article');
  card.className = `run-card ${statusClass(run)}`;
  const releaseTag = extractReleaseTag(run);

  const header = document.createElement('header');
  const heading = document.createElement('h3');
  heading.textContent = `Run #${run.run_number} · ${statusLabel(run)}`;
  const time = document.createElement('span');
  time.textContent = new Date(run.created_at).toLocaleString();
  header.append(heading, time);
  card.appendChild(header);

  const titleP = document.createElement('p');
  titleP.textContent = run.display_title || run.name;
  card.appendChild(titleP);

  const metaP = document.createElement('p');
  metaP.className = 'muted';
  metaP.textContent = `触发人：${run.actor?.login || 'unknown'}${releaseTag ? ` · Release Tag：${releaseTag}` : ''}`;
  card.appendChild(metaP);

  const linkP = document.createElement('p');
  const a = document.createElement('a');
  a.href = run.html_url;
  a.target = '_blank';
  a.rel = 'noreferrer';
  a.textContent = '打开工作流运行详情';
  linkP.appendChild(a);
  card.appendChild(linkP);

  card.appendChild(attachLogViewerButton(card, run.id, linkP));

  if (fromHistory) {
    const refreshBtn = document.createElement('button');
    refreshBtn.type = 'button';
    refreshBtn.className = 'secondary';
    refreshBtn.textContent = '刷新状态';
    refreshBtn.addEventListener('click', async () => {
      const token = document.querySelector('#pat').value.trim();
      if (!token) {
        refreshBtn.textContent = '请先填写 PAT';
        return;
      }
      refreshBtn.textContent = '刷新中…';
      refreshBtn.disabled = true;
      try {
        await ensureRepositoryMetadata(token);
        const updated = await githubFetch(
          `/repos/${state.owner}/${state.repo}/actions/runs/${run.id}`,
          token,
        );
        upsertHistoryEntry({
          runId: updated.id,
          runNumber: updated.run_number,
          status: updated.status,
          conclusion: updated.conclusion,
        });
        renderHistory();
      } catch (err) {
        refreshBtn.textContent = `失败: ${err.message}`;
        refreshBtn.disabled = false;
      }
    });
    card.appendChild(refreshBtn);
  }

  return card;
}

function renderRunList(runs) {
  runListNode.className = 'run-list';
  runListNode.innerHTML = '';

  if (!runs.length) {
    runListNode.classList.add('empty');
    runListNode.textContent = '未找到 workflow_dispatch 任务。';
    return;
  }

  runs.forEach((run) => {
    runListNode.appendChild(buildRunCard(run, false));
  });
}

function renderHistory() {
  const entries = loadHistory();
  historyListNode.className = 'run-list';
  historyListNode.innerHTML = '';

  if (!entries.length) {
    historyListNode.classList.add('empty');
    historyListNode.textContent = '暂无本地历史记录。';
    return;
  }

  entries.forEach((entry) => {
    // Reconstruct a run-like object from stored data
    const run = {
      id: entry.runId,
      run_number: entry.runNumber,
      status: entry.status || 'completed',
      conclusion: entry.conclusion || null,
      display_title: [entry.owner, entry.platform, entry.arch, entry.releaseTag].filter(Boolean).join(' | '),
      name: entry.releaseTag || '',
      html_url: entry.htmlUrl || `https://github.com/${entry.owner}/${entry.repo}/actions/runs/${entry.runId}`,
      created_at: entry.triggeredAt || new Date().toISOString(),
      actor: { login: entry.owner || 'unknown' },
    };
    historyListNode.appendChild(buildRunCard(run, true));
  });
}

// ── Run polling and triggering ──────────────────────────────────────────────

async function findTriggeredRun(token, releaseTag) {
  const payload = await githubFetch(
    `/repos/${state.owner}/${state.repo}/actions/workflows/build.yml/runs?event=workflow_dispatch&per_page=20`,
    token,
  );

  return (payload.workflow_runs || []).find((run) => (run.display_title || '').includes(releaseTag)) || null;
}

async function refreshRuns() {
  const token = document.querySelector('#pat').value.trim();
  if (!token) {
    throw new Error('请输入 PAT 后再刷新任务列表。');
  }

  state.token = token;
  await ensureRepositoryMetadata(token);
  await ensureWriteAccess(token);

  const payload = await githubFetch(
    `/repos/${state.owner}/${state.repo}/actions/workflows/build.yml/runs?event=workflow_dispatch&per_page=10`,
    token,
  );
  renderRunList(payload.workflow_runs || []);
}

function schedulePoll(runId, releaseTag, token, failures = 0) {
  if (state.pollHandle) {
    window.clearTimeout(state.pollHandle);
  }

  state.pollHandle = window.setTimeout(() => {
    pollRun(runId, releaseTag, token).catch((error) => {
      if (failures + 1 >= POLL_MAX_FAILURES) {
        setMessage(taskStatusNode, 'status-error', `状态轮询已停止：${error.message}`);
        return;
      }
      schedulePoll(runId, releaseTag, token, failures + 1);
    });
  }, POLL_INTERVAL_MS * (failures + 1));
}

async function pollRun(runId, releaseTag, token) {
  if (state.pollHandle) {
    window.clearTimeout(state.pollHandle);
  }

  const run = await githubFetch(`/repos/${state.owner}/${state.repo}/actions/runs/${runId}`, token);
  const links = run.status === 'completed' ? await loadRunDownloads(runId, releaseTag, token) : [];
  renderTaskStatus(run, links);

  // Keep history up-to-date
  upsertHistoryEntry({
    runId: run.id,
    runNumber: run.run_number,
    status: run.status,
    conclusion: run.conclusion,
  });
  renderHistory();

  if (run.status !== 'completed') {
    schedulePoll(runId, releaseTag, token);
  }
}

async function handleSubmit(event) {
  event.preventDefault();
  const formData = new FormData(form);

  const token = String(formData.get('pat') || '').trim();
  const sourceRepository = String(formData.get('sourceRepository') || '').trim();
  const sourceRef = String(formData.get('sourceRef') || '').trim();
  const targetPlatform = String(formData.get('targetPlatform') || '').trim();
  const targetArch = String(formData.get('targetArch') || '').trim();
  const packageFormat = String(formData.get('packageFormat') || '').trim();
  const configureOptions = String(formData.get('configureOptions') || '').trim();

  if (!token || !sourceRepository || !targetPlatform || !targetArch || !packageFormat || !configureOptions) {
    throw new Error('请完整填写所有必填字段。');
  }

  state.token = token;
  await ensureRepositoryMetadata(token);
  await ensureWriteAccess(token);

  const releaseTag = makeReleaseTag(targetPlatform, targetArch);
  state.releaseTag = releaseTag;

  setMessage(taskStatusNode, 'status-warn', '任务已提交，正在等待 GitHub Actions 生成运行记录…');

  const dispatch = await githubFetch(`/repos/${state.owner}/${state.repo}/actions/workflows/build.yml/dispatches`, token, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      ref: state.defaultBranch,
      return_run_details: true,
      inputs: {
        source_repository: sourceRepository,
        source_ref: sourceRef,
        target_platform: targetPlatform,
        target_arch: targetArch,
        package_format: packageFormat,
        configure_options: configureOptions,
        release_tag: releaseTag,
      },
    }),
  });

  let run = null;
  if (dispatch?.workflow_run_id) {
    run = await githubFetch(`/repos/${state.owner}/${state.repo}/actions/runs/${dispatch.workflow_run_id}`, token);
  }
  // Fallback for responses without run details: look the run up by its release tag.
  for (let attempt = 0; !run && attempt < 12; attempt += 1) {
    run = await findTriggeredRun(token, releaseTag);
    if (!run) {
      await new Promise((resolve) => window.setTimeout(resolve, 5000));
    }
  }

  if (!run) {
    throw new Error('Workflow 已触发，但暂时未查询到对应运行记录。请稍后点击"刷新任务状态"。');
  }

  state.runId = run.id;

  // Persist task to local history (no PAT saved)
  upsertHistoryEntry({
    runId: run.id,
    runNumber: run.run_number,
    owner: state.owner,
    repo: state.repo,
    releaseTag,
    platform: targetPlatform,
    arch: targetArch,
    sourceRepository,
    sourceRef,
    configureOptions,
    triggeredAt: run.created_at || new Date().toISOString(),
    status: run.status,
    conclusion: run.conclusion || null,
    htmlUrl: run.html_url,
  });
  renderHistory();

  await pollRun(run.id, releaseTag, token);
  await refreshRuns();
}

// ── Arch options per platform ────────────────────────────────────────────────

const ARCH_OPTIONS = {
  linux:   [['x86_64', 'x86_64'], ['x86', 'x86 (32-bit)'], ['arm64', 'arm64 (AArch64)'], ['armv7', 'armv7 (ARM 32-bit)']],
  macos:   [['x86_64', 'x86_64 (Intel)'], ['arm64', 'arm64 (Apple Silicon)'], ['universal', 'Universal (fat binary)']],
  windows: [['x86_64', 'x86_64'], ['x86', 'x86 (32-bit，实验性)'], ['arm64', 'arm64 (AArch64)']],
  all:     [['x86_64', 'x86_64'], ['arm64', 'arm64'], ['universal', 'Universal (macOS fat + x86_64 others)']],
};

const targetPlatformSelect = document.querySelector('#target-platform');
const targetArchSelect = document.querySelector('#target-arch');

function updateArchOptions() {
  const platform = targetPlatformSelect.value;
  const options = ARCH_OPTIONS[platform] || ARCH_OPTIONS.linux;
  const current = targetArchSelect.value;
  targetArchSelect.innerHTML = '';
  options.forEach(([value, label]) => {
    const opt = document.createElement('option');
    opt.value = value;
    opt.textContent = label;
    if (value === current) opt.selected = true;
    targetArchSelect.appendChild(opt);
  });
}

targetPlatformSelect.addEventListener('change', updateArchOptions);
updateArchOptions();

updateDetectedRepo();
defaultBranchNode.textContent = '待使用 PAT 查询';
renderHistory();

applyPresetButton.addEventListener('click', normalizeConfigurePreset);
const submitButton = form.querySelector('button[type="submit"]');
form.addEventListener('submit', (event) => {
  submitButton.disabled = true;
  handleSubmit(event)
    .catch((error) => {
      setMessage(taskStatusNode, 'status-error', error.message);
    })
    .finally(() => {
      submitButton.disabled = false;
    });
});
refreshRunsButton.addEventListener('click', () => {
  refreshRuns().catch((error) => {
    setMessage(runListNode, 'empty status-error', error.message);
  });
});
