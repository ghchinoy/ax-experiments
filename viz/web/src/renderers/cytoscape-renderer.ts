import cytoscape from 'cytoscape';
import fcose from 'cytoscape-fcose';
import { Renderer, GraphState, GraphEdge } from '../types';

try {
  cytoscape.use(fcose);
} catch {
  // Already registered
}

function getCytoscapeStyle(theme: 'dark' | 'light'): cytoscape.StylesheetStyle[] {
  const isDark = theme === 'dark';
  return [
    {
      selector: 'node',
      style: {
        'background-color': 'data(color)',
        label: 'data(label)',
        color: isDark ? '#f8fafc' : '#0f172a',
        'font-size': '10px',
        'font-weight': 'bold',
        'text-valign': 'bottom',
        'text-margin-y': 5,
        'text-wrap': 'wrap',
        'text-max-width': '110px',
        'text-background-color': isDark ? '#090d16' : '#ffffff',
        'text-background-opacity': 0.92,
        'text-background-padding': '3px',
        'text-background-shape': 'roundrectangle',
        'text-border-color': isDark ? '#334155' : '#cbd5e1',
        'text-border-width': 1,
        'text-border-opacity': 0.8,
        width: 32,
        height: 32,
      },
    },
    {
      selector: 'node[phase = "Running"]',
      style: {
        'border-width': 3,
        'border-color': isDark ? '#86efac' : '#16a34a',
      },
    },
    {
      selector: 'node[phase = "Suspended"]',
      style: {
        'border-width': 2.5,
        'border-color': '#f97316',
        'border-style': 'dashed',
      },
    },
    {
      selector: 'node.active',
      style: {
        'border-width': 4,
        'border-color': isDark ? '#38bdf8' : '#0284c7',
        'border-style': 'double',
      },
    },
    {
      selector: 'edge',
      style: {
        width: 2,
        'line-color': isDark ? '#334155' : '#cbd5e1',
        'target-arrow-color': isDark ? '#334155' : '#cbd5e1',
        'target-arrow-shape': 'triangle',
        'curve-style': 'bezier',
        'control-point-step-size': 50,
        'arrow-scale': 1.1,
      },
    },
    {
      selector: 'edge[kind = "spawn"]',
      style: {
        width: 1.5,
        'line-color': isDark ? '#334155' : '#cbd5e1',
        'target-arrow-color': isDark ? '#475569' : '#94a3b8',
      },
    },
    {
      selector: 'edge[kind = "control"]',
      style: {
        width: 2.5,
        'line-color': isDark ? '#a855f7' : '#9333ea',
        'target-arrow-color': isDark ? '#a855f7' : '#9333ea',
        label: 'data(label)',
        'font-size': '9px',
        'font-weight': 'bold',
        color: isDark ? '#c084fc' : '#7e22ce',
        'text-rotation': 'autorotate',
        'text-background-color': isDark ? '#090d16' : '#ffffff',
        'text-background-opacity': 0.92,
        'text-background-padding': '3px',
        'text-background-shape': 'roundrectangle',
        'text-border-color': isDark ? '#581c87' : '#d8b4fe',
        'text-border-width': 1,
      },
    },
    {
      selector: 'edge[kind = "msg"][?active]',
      style: {
        width: 4,
        'line-color': isDark ? '#38bdf8' : '#0284c7',
        'target-arrow-color': isDark ? '#38bdf8' : '#0284c7',
        'line-style': 'dashed',
        label: 'data(label)',
        'font-size': '11px',
        'font-weight': 'bold',
        color: isDark ? '#7dd3fc' : '#0369a1',
        'text-rotation': 'autorotate',
        'text-background-color': isDark ? '#090d16' : '#ffffff',
        'text-background-opacity': 0.95,
        'text-background-padding': '4px',
        'text-background-shape': 'roundrectangle',
        'text-border-color': isDark ? '#0284c7' : '#38bdf8',
        'text-border-width': 1,
        'z-index': 999,
      },
    },
    {
      selector: 'edge[kind = "msg"][!active]',
      style: {
        width: 2,
        'line-color': isDark ? '#0369a1' : '#38bdf8',
        'target-arrow-color': isDark ? '#0369a1' : '#38bdf8',
        'line-style': 'dashed',
      },
    },
  ];
}

export class CytoscapeRenderer implements Renderer {
  private cy: cytoscape.Core | null = null;
  private container: HTMLElement | null = null;
  private resizeObserver: ResizeObserver | null = null;
  private activePulseEdge?: GraphEdge;
  private currentTheme: 'dark' | 'light' = 'dark';

  init(container: HTMLElement): void {
    this.container = container;
    container.innerHTML = '';
    this.activePulseEdge = undefined;
    container.style.backgroundColor = this.currentTheme === 'dark' ? '#090d16' : '#f8fafc';

    this.cy = cytoscape({
      container: container,
      minZoom: 0.2,
      maxZoom: 4.0, // Allow smooth user mouse-scroll zooming!
      style: getCytoscapeStyle(this.currentTheme),
      layout: {
        name: 'fcose',
        animate: false,
        randomize: true,
        fit: true,
        padding: 50,
        nodeDimensionsIncludeLabels: true,
        idealEdgeLength: 170,
        nodeRepulsion: 10000,
        nodeSeparation: 90,
      } as any,
    });

    this.resizeObserver = new ResizeObserver(() => {
      if (this.cy) {
        this.cy.resize();
      }
    });
    this.resizeObserver.observe(container);
  }

  setTheme(theme: 'dark' | 'light'): void {
    this.currentTheme = theme;
    if (this.container) {
      this.container.style.backgroundColor = theme === 'dark' ? '#090d16' : '#f8fafc';
    }
    if (this.cy) {
      this.cy.style(getCytoscapeStyle(theme) as any);
    }
  }

  update(state: GraphState): void {
    if (!this.cy) return;

    this.activePulseEdge = state.activePulseEdge;

    const existingNodeIds = new Set(this.cy.nodes().map((n) => n.id()));
    const existingEdgeIds = new Set(this.cy.edges().map((e) => e.id()));

    const targetNodeIds = new Set(state.nodes.map((n) => n.id));
    const targetEdgeIds = new Set(state.edges.map((e) => e.id));

    // Batch updates
    this.cy.batch(() => {
      // Remove deleted nodes and edges
      for (const id of existingNodeIds) {
        if (!targetNodeIds.has(id)) {
          this.cy?.$id(id).remove();
        }
      }
      for (const id of existingEdgeIds) {
        if (!targetEdgeIds.has(id)) {
          this.cy?.$id(id).remove();
        }
      }

      // Add or update nodes with radial initial layout
      const totalNodes = state.nodes.length || 1;
      const targetList = Array.from(targetNodeIds);

      state.nodes.forEach((n) => {
        const ip = n.workerIP ? `\n${n.workerIP}` : '';
        const label = `${n.label || n.id}${ip}`;

        if (!existingNodeIds.has(n.id)) {
          const idx = targetList.indexOf(n.id);
          const angle = (idx / totalNodes) * 2 * Math.PI;
          const radius = n.role === 'host' ? 0 : 180;
          const initialPos = {
            x: 400 + radius * Math.cos(angle),
            y: 300 + radius * Math.sin(angle),
          };

          this.cy?.add({
            group: 'nodes',
            data: {
              id: n.id,
              label: label,
              color: n.color || '#94a3b8',
              phase: n.phase,
            },
            position: initialPos,
          });
        } else {
          const ele = this.cy?.$id(n.id);
          ele?.data('color', n.color);
          ele?.data('phase', n.phase);
          ele?.data('label', label);
        }
      });

      // Add or update edges
      for (const e of state.edges) {
        const isActive = this.activePulseEdge?.id === e.id || e.active;
        if (!existingEdgeIds.has(e.id)) {
          this.cy?.add({
            group: 'edges',
            data: {
              id: e.id,
              source: e.source,
              target: e.target,
              kind: e.kind,
              label: e.label,
              active: isActive,
            },
          });
        } else {
          const ele = this.cy?.$id(e.id);
          ele?.data('active', isActive);
        }
      }

      // Highlight active node
      this.cy?.nodes().removeClass('active');
      if (state.activeNodeId) {
        this.cy?.$id(state.activeNodeId).addClass('active');
      }
    });

    if (state.nodes.length !== existingNodeIds.size) {
      const layout = this.cy.layout({
        name: 'fcose',
        animate: true,
        animationDuration: 350,
        randomize: false,
        fit: true,
        padding: 50,
        nodeDimensionsIncludeLabels: true,
        idealEdgeLength: 170,
        nodeRepulsion: 10000,
        nodeSeparation: 90,
        stop: () => {
          // Clamp initial fit zoom so small graphs don't feel huge
          if (this.cy && this.cy.zoom() > 1.15) {
            this.cy.zoom(1.15);
            this.cy.center();
          }
        },
      } as any);
      layout.run();
    }
  }

  reset(): void {
    if (this.cy) {
      this.cy.fit(undefined, 50);
      if (this.cy.zoom() > 1.15) {
        this.cy.zoom(1.15);
        this.cy.center();
      }
    }
  }

  destroy(): void {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
      this.resizeObserver = null;
    }
    if (this.cy) {
      this.cy.destroy();
      this.cy = null;
    }
  }
}
