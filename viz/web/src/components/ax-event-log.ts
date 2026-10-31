import { LitElement, html, css, PropertyValues } from 'lit';
import { TraceEvent } from '../types';

export class AxEventLog extends LitElement {
  static properties = {
    events: { type: Array },
    activeIndex: { type: Number },
  };

  declare events: TraceEvent[];
  declare activeIndex: number;

  constructor() {
    super();
    this.events = [];
    this.activeIndex = -1;
  }

  static styles = css`
    :host {
      display: flex;
      flex-direction: column;
      height: 100%;
      background: var(--bg-surface, #0f172a);
      border-left: 1px solid var(--border, #334155);
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 11px;
      color: var(--text-secondary, #94a3b8);
      transition: background 0.15s, border-color 0.15s, color 0.15s;
    }
    .header {
      padding: 10px 12px;
      background: var(--bg-card, #1e293b);
      border-bottom: 1px solid var(--border, #334155);
      font-weight: 600;
      color: var(--text-primary, #f8fafc);
      display: flex;
      justify-content: space-between;
    }
    .list {
      flex: 1;
      overflow-y: auto;
      padding: 4px 0;
    }
    .item {
      padding: 6px 12px;
      border-bottom: 1px solid var(--border-item, #1e293b);
      cursor: pointer;
      display: flex;
      gap: 8px;
      align-items: center;
      transition: background 0.1s;
    }
    .item:hover {
      background: var(--bg-card, #1e293b);
    }
    .item.active {
      background: var(--active-bg, #1e3a5f);
      color: var(--accent, #38bdf8);
      border-left: 3px solid var(--accent, #38bdf8);
    }
    .badge {
      padding: 2px 6px;
      border-radius: 4px;
      font-size: 9px;
      text-transform: uppercase;
      font-weight: 700;
      letter-spacing: 0.5px;
    }
    .badge-ax {
      background: var(--badge-ax-bg, #064e3b);
      color: var(--badge-ax-fg, #34d399);
    }
    .badge-controller {
      background: var(--badge-ctl-bg, #581c87);
      color: var(--badge-ctl-fg, #c084fc);
    }
    .badge-recipe {
      background: var(--badge-rcp-bg, #0c4a6e);
      color: var(--badge-rcp-fg, #38bdf8);
    }
    .time {
      color: var(--text-muted, #64748b);
      min-width: 42px;
    }
    .label {
      flex: 1;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
  `;

  updated(changedProperties: PropertyValues<this>) {
    if (changedProperties.has('activeIndex') && this.activeIndex >= 0) {
      const activeEl = this.shadowRoot?.querySelector('.item.active');
      activeEl?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }

  private selectEvent(e: TraceEvent) {
    this.dispatchEvent(
      new CustomEvent('seek', {
        detail: { time: e.t },
        bubbles: true,
        composed: true,
      })
    );
  }

  render() {
    return html`
      <div class="header">
        <span>Event Stream</span>
        <span>${this.events.length} events</span>
      </div>
      <div class="list">
        ${this.events.map((e, idx) => {
          const isActive = idx === this.activeIndex;
          const badgeClass = `badge badge-${e.src}`;
          return html`
            <div
              class="item ${isActive ? 'active' : ''}"
              @click=${() => this.selectEvent(e)}
              title="Click to seek to ${e.t.toFixed(2)}s"
            >
              <span class="time">${e.t.toFixed(2)}s</span>
              <span class="${badgeClass}">${e.src}</span>
              <span class="label">${e.label || e.kind}</span>
            </div>
          `;
        })}
      </div>
    `;
  }
}

customElements.define('ax-event-log', AxEventLog);

declare global {
  interface HTMLElementTagNameMap {
    'ax-event-log': AxEventLog;
  }
}
