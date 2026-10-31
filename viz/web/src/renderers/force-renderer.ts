import ForceGraph from 'force-graph';
import { Renderer, GraphState, GraphEdge } from '../types';

export class ForceGraphRenderer implements Renderer {
  private fgInstance: any = null;
  private container: HTMLElement | null = null;
  private resizeObserver: ResizeObserver | null = null;
  private nodeMap: Map<string, any> = new Map();
  private linkMap: Map<string, any> = new Map();
  private activeNodeId?: string;
  private activePulseEdge?: GraphEdge;
  private currentTheme: 'dark' | 'light' = 'dark';
  private expectedNodes: number = 4;

  init(container: HTMLElement): void {
    this.container = container;
    container.innerHTML = '';
    this.nodeMap.clear();
    this.linkMap.clear();
    this.activeNodeId = undefined;
    this.activePulseEdge = undefined;

    const width = container.clientWidth || 800;
    const height = container.clientHeight || 500;
    const isDark = this.currentTheme === 'dark';

    this.fgInstance = (ForceGraph as any)()(container)
      .width(width)
      .height(height)
      .backgroundColor(isDark ? '#090d16' : '#f8fafc')
      .nodeId('id')
      .minZoom(0.2)
      .maxZoom(3.0)
      .d3VelocityDecay(0.35)
      .nodeLabel((node: any) => {
        const ip = node.workerIP ? `\nIP: ${node.workerIP}` : '';
        return `${node.label} (${node.role})\nPhase: ${node.phase}${ip}`;
      })
      .nodeCanvasObject((node: any, ctx: CanvasRenderingContext2D, globalScale: number) => {
        const r = Math.sqrt(node.val || 12) * 3.8;
        const isActive = node.id === this.activeNodeId;
        const isDarkTheme = this.currentTheme === 'dark';

        // Glowing animated ripple/halo for active node
        if (isActive) {
          ctx.save();
          ctx.beginPath();
          ctx.arc(node.x, node.y, r + 6 / globalScale, 0, 2 * Math.PI, false);
          ctx.strokeStyle = isDarkTheme ? '#38bdf8' : '#0284c7';
          ctx.lineWidth = 3 / globalScale;
          ctx.shadowColor = isDarkTheme ? '#38bdf8' : '#0284c7';
          ctx.shadowBlur = 16;
          ctx.stroke();
          ctx.restore();
        }

        // Main node circle
        ctx.beginPath();
        ctx.arc(node.x, node.y, r, 0, 2 * Math.PI, false);
        ctx.fillStyle = node.color || '#94a3b8';
        ctx.fill();

        // Outer status ring
        if (node.phase === 'Running') {
          ctx.beginPath();
          ctx.arc(node.x, node.y, r + 2 / globalScale, 0, 2 * Math.PI, false);
          ctx.strokeStyle = isDarkTheme ? '#86efac' : '#16a34a';
          ctx.lineWidth = 2.2 / globalScale;
          ctx.stroke();
        } else if (node.phase === 'Suspended') {
          ctx.beginPath();
          ctx.arc(node.x, node.y, r + 2 / globalScale, 0, 2 * Math.PI, false);
          ctx.strokeStyle = '#f97316';
          ctx.lineWidth = 2 / globalScale;
          ctx.stroke();
        }

        // Pill badge background for label
        const label = node.label || node.id;
        const fontSize = Math.max(9, 10 / globalScale);
        ctx.font = `600 ${fontSize}px sans-serif`;
        ctx.textAlign = 'center';
        ctx.textBaseline = 'top';

        const textWidth = ctx.measureText(label).width;
        ctx.fillStyle = isDarkTheme ? 'rgba(9, 13, 22, 0.88)' : 'rgba(255, 255, 255, 0.92)';
        ctx.fillRect(
          node.x - textWidth / 2 - 4 / globalScale,
          node.y + r + 3 / globalScale,
          textWidth + 8 / globalScale,
          fontSize + 3 / globalScale
        );
        ctx.strokeStyle = isDarkTheme ? '#334155' : '#cbd5e1';
        ctx.lineWidth = 1 / globalScale;
        ctx.strokeRect(
          node.x - textWidth / 2 - 4 / globalScale,
          node.y + r + 3 / globalScale,
          textWidth + 8 / globalScale,
          fontSize + 3 / globalScale
        );

        ctx.fillStyle = isDarkTheme ? '#f8fafc' : '#0f172a';
        ctx.fillText(label, node.x, node.y + r + 4 / globalScale);

        // Subtitle: worker IP or non-running phase
        const sub = node.workerIP || (node.phase && node.phase !== 'Running' ? node.phase : '');
        if (sub) {
          const subSize = Math.max(8, 8.5 / globalScale);
          ctx.font = `${subSize}px monospace`;
          ctx.fillStyle = isDarkTheme ? '#94a3b8' : '#64748b';
          ctx.fillText(sub, node.x, node.y + r + fontSize + 8 / globalScale);
        }
      })
      .nodeCanvasObjectMode(() => 'after')
      .linkLabel((link: any) => link.label || '')
      .linkColor((link: any) => {
        const isDarkTheme = this.currentTheme === 'dark';
        if (link.active) return isDarkTheme ? '#38bdf8' : '#0284c7';
        if (link.kind === 'msg') return isDarkTheme ? '#0284c7' : '#0ea5e9';
        if (link.kind === 'control') return isDarkTheme ? '#a855f7' : '#9333ea';
        return isDarkTheme ? '#334155' : '#cbd5e1';
      })
      .linkWidth((link: any) => {
        if (link.active) return 3.5;
        if (link.kind === 'msg') return 2;
        return 1.5;
      })
      .linkDirectionalParticles((link: any) => {
        if (link.active) return 8;
        if (link.kind === 'msg') return 4;
        return 0;
      })
      .linkDirectionalParticleWidth((link: any) => (link.active ? 4 : 2.5))
      .linkDirectionalParticleSpeed((link: any) => (link.active ? 0.035 : 0.015))
      .linkDirectionalParticleColor((link: any) => {
        const isDarkTheme = this.currentTheme === 'dark';
        if (link.active) return isDarkTheme ? '#7dd3fc' : '#0284c7';
        return isDarkTheme ? '#38bdf8' : '#0ea5e9';
      })
      .linkCanvasObjectMode(() => 'after')
      .linkCanvasObject((link: any, ctx: CanvasRenderingContext2D, globalScale: number) => {
        // Only render label on ACTIVE message edges or control edges to prevent collision
        if (!link.label || (!link.active && link.kind !== 'control') || link.kind === 'spawn') return;
        const start = link.source;
        const end = link.target;
        if (!start || !end || typeof start.x !== 'number' || typeof end.x !== 'number') return;

        const isDarkTheme = this.currentTheme === 'dark';
        const dx = end.x - start.x;
        const dy = end.y - start.y;
        const len = Math.hypot(dx, dy) || 1;
        const nx = -dy / len;
        const ny = dx / len;
        const offset = 14 / globalScale;

        const midX = (start.x + end.x) / 2 + nx * offset;
        const midY = (start.y + end.y) / 2 + ny * offset;
        const fontSize = Math.max(9, 10 / globalScale);
        ctx.font = `600 ${fontSize}px sans-serif`;

        const textWidth = ctx.measureText(link.label).width;
        ctx.fillStyle = isDarkTheme ? 'rgba(9, 13, 22, 0.92)' : 'rgba(255, 255, 255, 0.95)';
        ctx.fillRect(midX - textWidth / 2 - 4, midY - fontSize / 2 - 3, textWidth + 8, fontSize + 6);
        ctx.strokeStyle = link.active ? (isDarkTheme ? '#38bdf8' : '#0284c7') : (isDarkTheme ? '#7c3aed' : '#9333ea');
        ctx.lineWidth = 1;
        ctx.strokeRect(midX - textWidth / 2 - 4, midY - fontSize / 2 - 3, textWidth + 8, fontSize + 6);

        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = link.active ? (isDarkTheme ? '#38bdf8' : '#0284c7') : (isDarkTheme ? '#c084fc' : '#7e22ce');
        ctx.fillText(link.label, midX, midY);
      });

    // Moderate repulsion and balanced distance so nodes stay inside viewport comfortably
    const chargeForce = this.fgInstance.d3Force('charge');
    if (chargeForce && typeof chargeForce.strength === 'function') {
      chargeForce.strength(-280);
    }
    const linkForce = this.fgInstance.d3Force('link');
    if (linkForce && typeof linkForce.distance === 'function') {
      linkForce.distance((link: any) => (link.kind === 'msg' ? 120 : 85));
    }

    this.setInitialZoom(this.expectedNodes);

    this.resizeObserver = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const { width, height } = entry.contentRect;
        if (width > 0 && height > 0 && this.fgInstance) {
          this.fgInstance.width(width).height(height);
        }
      }
    });
    this.resizeObserver.observe(container);
  }

  setInitialZoom(nodeCount: number): void {
    this.expectedNodes = nodeCount;
    if (!this.fgInstance) return;

    // Room to accommodate future node count without being super-zoomed in to host
    let targetZoom = 1.0;
    if (nodeCount >= 8) targetZoom = 0.72;
    else if (nodeCount >= 5) targetZoom = 0.82;
    else targetZoom = 0.92;

    this.fgInstance.centerAt(0, 0, 200);
    this.fgInstance.zoom(targetZoom, 200);
  }

  setTheme(theme: 'dark' | 'light'): void {
    this.currentTheme = theme;
    if (this.fgInstance) {
      this.fgInstance.backgroundColor(theme === 'dark' ? '#090d16' : '#f8fafc');
      if (typeof this.fgInstance.refresh === 'function') {
        this.fgInstance.refresh();
      }
    }
  }

  update(state: GraphState): void {
    if (!this.fgInstance) return;

    this.activeNodeId = state.activeNodeId;
    this.activePulseEdge = state.activePulseEdge;

    const targetNodeIds = new Set(state.nodes.map((n) => n.id));
    const targetEdgeIds = new Set(state.edges.map((e) => e.id));

    let topologyChanged = false;
    if (targetNodeIds.size !== this.nodeMap.size || targetEdgeIds.size !== this.linkMap.size) {
      topologyChanged = true;
    } else {
      for (const id of targetNodeIds) {
        if (!this.nodeMap.has(id)) {
          topologyChanged = true;
          break;
        }
      }
      if (!topologyChanged) {
        for (const id of targetEdgeIds) {
          if (!this.linkMap.has(id)) {
            topologyChanged = true;
            break;
          }
        }
      }
    }

    if (topologyChanged) {
      // Remove deleted nodes
      for (const id of Array.from(this.nodeMap.keys())) {
        if (!targetNodeIds.has(id)) {
          this.nodeMap.delete(id);
        }
      }
      // Add or update nodes preserving positions
      for (const n of state.nodes) {
        if (this.nodeMap.has(n.id)) {
          const existing = this.nodeMap.get(n.id);
          Object.assign(existing, n);
        } else {
          this.nodeMap.set(n.id, { ...n });
        }
      }

      // Remove deleted edges
      for (const id of Array.from(this.linkMap.keys())) {
        if (!targetEdgeIds.has(id)) {
          this.linkMap.delete(id);
        }
      }
      // Add or update edges
      for (const e of state.edges) {
        const isActive = this.activePulseEdge?.id === e.id || e.active;
        if (this.linkMap.has(e.id)) {
          const existing = this.linkMap.get(e.id);
          Object.assign(existing, {
            source: e.source,
            target: e.target,
            kind: e.kind,
            label: e.label,
            active: isActive,
          });
        } else {
          this.linkMap.set(e.id, {
            id: e.id,
            source: e.source,
            target: e.target,
            kind: e.kind,
            label: e.label,
            active: isActive,
          });
        }
      }

      this.fgInstance.graphData({
        nodes: Array.from(this.nodeMap.values()),
        links: Array.from(this.linkMap.values()),
      });
      if (typeof this.fgInstance.d3ReheatSimulation === 'function') {
        this.fgInstance.d3ReheatSimulation();
      }
    } else {
      // Mutate properties in-place
      for (const n of state.nodes) {
        const existing = this.nodeMap.get(n.id);
        if (existing) {
          Object.assign(existing, n);
        }
      }
      for (const e of state.edges) {
        const existing = this.linkMap.get(e.id);
        if (existing) {
          const isActive = this.activePulseEdge?.id === e.id || e.active;
          Object.assign(existing, {
            kind: e.kind,
            label: e.label,
            active: isActive,
          });
        }
      }
      if (typeof this.fgInstance.refresh === 'function') {
        this.fgInstance.refresh();
      }
    }
  }

  reset(): void {
    if (this.fgInstance) {
      this.setInitialZoom(this.expectedNodes);
    }
  }

  destroy(): void {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
      this.resizeObserver = null;
    }
    if (this.container) {
      this.container.innerHTML = '';
      this.container = null;
    }
    this.nodeMap.clear();
    this.linkMap.clear();
    this.fgInstance = null;
  }
}
