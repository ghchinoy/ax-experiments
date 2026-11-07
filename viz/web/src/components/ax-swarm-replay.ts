import { LitElement, html, css } from 'lit';
import { TraceEngine } from '../trace-engine';
import { ForceGraphRenderer } from '../renderers/force-renderer';
import { CytoscapeRenderer } from '../renderers/cytoscape-renderer';
import { Renderer, GraphState, TraceEvent } from '../types';
import './ax-event-log';

export class AxSwarmReplay extends LitElement {
  static properties = {
    src: { type: String },
    rendererType: { state: true },
    themeMode: { state: true },
    effectiveTheme: { state: true },
    currentTime: { state: true },
    duration: { state: true },
    isPlaying: { state: true },
    speed: { state: true },
    events: { state: true },
    activeIndex: { state: true },
    nodeCount: { state: true },
    edgeCount: { state: true },
  };

  declare src: string;
  declare rendererType: 'force' | 'cytoscape';
  declare themeMode: 'auto' | 'dark' | 'light';
  declare effectiveTheme: 'dark' | 'light';
  declare currentTime: number;
  declare duration: number;
  declare isPlaying: boolean;
  declare speed: number;
  declare events: TraceEvent[];
  declare activeIndex: number;
  declare nodeCount: number;
  declare edgeCount: number;

  private engine: TraceEngine;
  private renderer: Renderer | null = null;
  private mediaQuery: MediaQueryList | null = null;
  private mediaQueryListener: (() => void) | null = null;

  constructor() {
    super();
    this.src = 'traces/05-debate.jsonl';
    this.rendererType = 'force';
    this.currentTime = 0;
    this.duration = 0;
    this.isPlaying = false;
    this.speed = 1.0;
    this.events = [];
    this.activeIndex = -1;
    this.nodeCount = 0;
    this.edgeCount = 0;
    this.engine = new TraceEngine();

    const savedTheme = (localStorage.getItem('ax-viz-theme') as 'auto' | 'dark' | 'light') || 'auto';
    this.themeMode = savedTheme;
    this.effectiveTheme = 'dark';
  }

  static styles = css`
    :host {
      --bg-main: #090d16;
      --bg-surface: #0f172a;
      --bg-card: #1e293b;
      --bg-footer: #0b0f19;
      --border: #1e293b;
      --border-input: #334155;
      --border-item: #1e293b;
      --text-primary: #f8fafc;
      --text-secondary: #94a3b8;
      --text-muted: #64748b;
      --accent: #38bdf8;
      --accent-hover: #0284c7;
      --badge-bg: #0369a1;
      --badge-text: #e0f2fe;
      --active-bg: #1e3a5f;
      --badge-ax-bg: #064e3b;
      --badge-ax-fg: #34d399;
      --badge-ctl-bg: #581c87;
      --badge-ctl-fg: #c084fc;
      --badge-rcp-bg: #0c4a6e;
      --badge-rcp-fg: #38bdf8;

      display: flex;
      flex-direction: column;
      height: 100vh;
      background: var(--bg-main);
      color: var(--text-primary);
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      transition: background 0.15s, color 0.15s;
    }

    :host([theme='light']) {
      --bg-main: #f8fafc;
      --bg-surface: #ffffff;
      --bg-card: #f1f5f9;
      --bg-footer: #f1f5f9;
      --border: #e2e8f0;
      --border-input: #cbd5e1;
      --border-item: #f1f5f9;
      --text-primary: #0f172a;
      --text-secondary: #475569;
      --text-muted: #94a3b8;
      --accent: #0284c7;
      --accent-hover: #0369a1;
      --badge-bg: #e0f2fe;
      --badge-text: #0369a1;
      --active-bg: #e0f2fe;
      --badge-ax-bg: #dcfce7;
      --badge-ax-fg: #15803d;
      --badge-ctl-bg: #f3e8ff;
      --badge-ctl-fg: #7e22ce;
      --badge-rcp-bg: #e0f2fe;
      --badge-rcp-fg: #0369a1;
    }

    .toolbar {
      display: flex;
      gap: 12px;
      align-items: center;
      padding: 10px 16px;
      background: var(--bg-surface);
      border-bottom: 1px solid var(--border);
      transition: background 0.15s, border-color 0.15s;
    }
    .title {
      font-weight: 700;
      font-size: 14px;
      letter-spacing: -0.3px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .badge {
      background: var(--badge-bg);
      color: var(--badge-text);
      font-size: 10px;
      padding: 2px 6px;
      border-radius: 4px;
      font-weight: 600;
    }
    select, button {
      background: var(--bg-card);
      color: var(--text-primary);
      border: 1px solid var(--border-input);
      padding: 6px 10px;
      border-radius: 6px;
      font-size: 12px;
      cursor: pointer;
      white-space: nowrap;
      transition: background 0.15s, border-color 0.15s, color 0.15s;
    }
    select.theme-select {
      min-width: 110px;
    }
    select:focus, button:focus {
      outline: 2px solid var(--accent);
    }
    button.primary {
      background: var(--accent);
      border-color: var(--accent-hover);
      color: #ffffff;
      font-weight: 600;
    }
    button.primary:hover {
      background: var(--accent-hover);
    }
    button.secondary {
      background: var(--bg-card);
      border-color: var(--border-input);
      color: var(--text-secondary);
      font-weight: 500;
    }
    button.secondary:hover {
      background: var(--border-input);
      color: var(--text-primary);
    }
    .scrubber {
      flex: 1;
      display: flex;
      align-items: center;
      gap: 10px;
      margin: 0 12px;
    }
    input[type='range'] {
      flex: 1;
      accent-color: var(--accent);
      cursor: pointer;
    }
    .time-display {
      font-family: ui-monospace, monospace;
      font-size: 12px;
      color: var(--text-secondary);
      min-width: 90px;
    }
    .content {
      display: flex;
      flex: 1;
      position: relative;
      overflow: hidden;
    }
    .graph-pane {
      flex: 1;
      position: relative;
      background: var(--bg-main);
      transition: background 0.15s;
    }
    .graph-container {
      width: 100%;
      height: 100%;
      position: relative;
    }
    .log-pane {
      width: 320px;
      height: 100%;
    }
    .footer {
      padding: 6px 16px;
      background: var(--bg-footer);
      border-top: 1px solid var(--border);
      font-size: 11px;
      color: var(--text-muted);
      display: flex;
      justify-content: space-between;
      align-items: center;
      transition: background 0.15s, border-color 0.15s;
    }
    .legend {
      display: flex;
      gap: 12px;
    }
    .legend-item {
      display: flex;
      align-items: center;
      gap: 5px;
    }
    .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
    }
  `;

  firstUpdated() {
    this.updateEffectiveTheme();

    if (window.matchMedia) {
      this.mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
      this.mediaQueryListener = () => {
        if (this.themeMode === 'auto') {
          this.updateEffectiveTheme();
        }
      };
      this.mediaQuery.addEventListener('change', this.mediaQueryListener);
    }

    this.engine.onUpdate((state: GraphState, t: number, idx: number) => {
      this.currentTime = t;
      this.activeIndex = idx;
      this.isPlaying = this.engine.getIsPlaying();
      this.nodeCount = state.nodes.length;
      this.edgeCount = state.edges.length;
      if (this.renderer) {
        this.renderer.update(state);
      }
    });

    this.setupRenderer();
    this.loadSelectedTrace(this.src);
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    if (this.mediaQuery && this.mediaQueryListener) {
      this.mediaQuery.removeEventListener('change', this.mediaQueryListener);
    }
    if (this.renderer) {
      this.renderer.destroy();
      this.renderer = null;
    }
    this.engine.pause();
  }

  private updateEffectiveTheme() {
    let theme: 'dark' | 'light' = 'dark';
    if (this.themeMode === 'auto') {
      if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
        theme = 'light';
      } else {
        theme = 'dark';
      }
    } else {
      theme = this.themeMode;
    }
    this.effectiveTheme = theme;
    this.setAttribute('theme', theme);

    if (this.renderer && typeof this.renderer.setTheme === 'function') {
      this.renderer.setTheme(theme);
    }
  }

  private setupRenderer() {
    const container = this.shadowRoot?.querySelector('.graph-container') as HTMLElement;
    if (!container) return;

    if (this.renderer) {
      this.renderer.destroy();
    }

    if (this.rendererType === 'force') {
      this.renderer = new ForceGraphRenderer();
    } else {
      this.renderer = new CytoscapeRenderer();
    }
    this.renderer.init(container);
    if (typeof this.renderer.setTheme === 'function') {
      this.renderer.setTheme(this.effectiveTheme);
    }
    if (typeof this.renderer.setInitialZoom === 'function') {
      this.renderer.setInitialZoom(this.engine.getMaxNodeCount() || 4);
    }

    const { state } = this.engine.computeStateAt(this.currentTime);
    this.renderer.update(state);
  }

  private async loadSelectedTrace(src: string) {
    this.src = src;
    await this.engine.loadTrace(src);
    this.duration = this.engine.getDuration();
    this.events = this.engine.getEvents();

    if (this.renderer && typeof this.renderer.setInitialZoom === 'function') {
      this.renderer.setInitialZoom(this.engine.getMaxNodeCount());
    }
  }

  private togglePlay() {
    if (this.isPlaying) {
      this.engine.pause();
      this.isPlaying = false;
    } else {
      this.engine.play();
      this.isPlaying = true;
    }
  }

  private resetReplay() {
    this.engine.pause();
    this.isPlaying = false;
    this.engine.seek(0);
    if (this.renderer && typeof this.renderer.reset === 'function') {
      this.renderer.reset();
    }
    if (this.renderer && typeof this.renderer.setInitialZoom === 'function') {
      this.renderer.setInitialZoom(this.engine.getMaxNodeCount());
    }
  }

  private onSeek(e: Event) {
    const target = e.target as HTMLInputElement;
    const val = parseFloat(target.value);
    this.engine.seek(val);
  }

  private onEventLogSeek(e: CustomEvent<{ time: number }>) {
    this.engine.seek(e.detail.time);
  }

  private onSpeedChange(e: Event) {
    const val = parseFloat((e.target as HTMLSelectElement).value);
    this.speed = val;
    this.engine.setSpeed(val);
  }

  private onTraceChange(e: Event) {
    const val = (e.target as HTMLSelectElement).value;
    this.loadSelectedTrace(val);
  }

  private onRendererChange(e: Event) {
    const val = (e.target as HTMLSelectElement).value as 'force' | 'cytoscape';
    this.rendererType = val;
    this.setupRenderer();
  }

  private onThemeChange(e: Event) {
    const val = (e.target as HTMLSelectElement).value as 'auto' | 'dark' | 'light';
    this.themeMode = val;
    localStorage.setItem('ax-viz-theme', val);
    this.updateEffectiveTheme();
  }

  render() {
    return html`
      <div class="toolbar">
        <div class="title">
          <span>AX Swarm Replayer</span>
          <span class="badge">Apple Container</span>
        </div>

        <select @change=${this.onTraceChange} .value=${this.src}>
          <option value="traces/01-hello-swarm.jsonl">01. Hello Swarm (8 nodes)</option>
          <option value="traces/04-review-panel.jsonl">04. AI Code Review Panel (3 agents)</option>
          <option value="traces/05-debate.jsonl">05. AI Red-Team Debate (Proposer & Critic)</option>
          <option value="traces/06-map-reduce.jsonl">06. Map-Reduce Synthesis (3 Mappers + Reducer)</option>
          <option value="traces/09-dgem-specialist-router.jsonl">09. dgem Scale-to-Zero Specialist Router (1-to-3)</option>
        </select>

        <select @change=${this.onRendererChange} .value=${this.rendererType}>
          <option value="force">Force Graph (Dynamic Particles)</option>
          <option value="cytoscape">Cytoscape CoSE (Structured Diagram)</option>
        </select>

        <button class="primary" @click=${this.togglePlay}>
          ${this.isPlaying ? 'Pause' : 'Play'}
        </button>

        <button class="secondary" @click=${this.resetReplay} title="Reset replay to start (t=0)">
          Reset
        </button>

        <div class="scrubber">
          <input
            type="range"
            min="0"
            max="${this.duration}"
            step="0.05"
            .value="${this.currentTime}"
            @input=${this.onSeek}
          />
          <span class="time-display">
            ${this.currentTime.toFixed(2)}s / ${this.duration.toFixed(2)}s
          </span>
        </div>

        <select @change=${this.onSpeedChange} .value=${this.speed.toFixed(1)}>
          <option value="0.5" ?selected=${this.speed === 0.5}>0.5x</option>
          <option value="1.0" ?selected=${this.speed === 1.0}>1.0x</option>
          <option value="2.0" ?selected=${this.speed === 2.0}>2.0x</option>
          <option value="4.0" ?selected=${this.speed === 4.0}>4.0x</option>
        </select>

        <select class="theme-select" @change=${this.onThemeChange} .value=${this.themeMode} title="Appearance Theme">
          <option value="auto" ?selected=${this.themeMode === 'auto'}>Theme: Auto</option>
          <option value="dark" ?selected=${this.themeMode === 'dark'}>Theme: Dark</option>
          <option value="light" ?selected=${this.themeMode === 'light'}>Theme: Light</option>
        </select>
      </div>

      <div class="content">
        <div class="graph-pane">
          <div class="graph-container"></div>
        </div>
        <div class="log-pane">
          <ax-event-log
            .events=${this.events}
            .activeIndex=${this.activeIndex}
            @seek=${this.onEventLogSeek}
          ></ax-event-log>
        </div>
      </div>

      <div class="footer">
        <div class="legend">
          <div class="legend-item"><span class="dot" style="background:#38bdf8"></span> Host</div>
          <div class="legend-item"><span class="dot" style="background:#a855f7"></span> Control Plane</div>
          <div class="legend-item"><span class="dot" style="background:#eab308"></span> Suspended/Pending</div>
          <div class="legend-item"><span class="dot" style="background:#22c55e"></span> Running (vmnet IP)</div>
        </div>
        <div>
          <span>Nodes: ${this.nodeCount} | Edges: ${this.edgeCount}</span>
        </div>
      </div>
    `;
  }
}

customElements.define('ax-swarm-replay', AxSwarmReplay);

declare global {
  interface HTMLElementTagNameMap {
    'ax-swarm-replay': AxSwarmReplay;
  }
}
