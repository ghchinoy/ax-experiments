// Trace Event definition matching SCHEMA.md
export interface TraceEvent {
  t: number;
  src: 'ax' | 'controller' | 'recipe';
  kind:
    | 'run.start'
    | 'run.end'
    | 'node.add'
    | 'node.phase'
    | 'node.ready'
    | 'node.remove'
    | 'ctl.step'
    | 'edge.exec'
    | 'edge.msg'
    | 'note';
  id?: string;
  from?: string;
  to?: string;
  phase?: string;
  workerIP?: string;
  role?: string;
  label?: string;
  meta?: Record<string, any>;
}

export interface GraphNode {
  id: string;
  label: string;
  role: string;
  phase: string;
  workerIP?: string;
  color?: string;
  val?: number; // size in force-graph
}

export interface GraphEdge {
  id: string;
  source: string;
  target: string;
  kind: string;
  label: string;
  active?: boolean;
}

export interface GraphState {
  nodes: GraphNode[];
  edges: GraphEdge[];
  activePulseEdge?: GraphEdge;
  activeNodeId?: string;
}

export interface Renderer {
  init(container: HTMLElement): void;
  update(state: GraphState): void;
  destroy(): void;
  reset?(): void;
  setInitialZoom?(nodeCount: number): void;
  setTheme?(theme: 'dark' | 'light'): void;
}
