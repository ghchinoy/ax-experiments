import { TraceEvent, GraphState, GraphNode, GraphEdge } from './types';

export class TraceEngine {
  private events: TraceEvent[] = [];
  private currentTime: number = 0;
  private duration: number = 0;
  private isPlaying: boolean = false;
  private speed: number = 1.0;
  private lastRafTime: number = 0;
  private onUpdateCallbacks: ((state: GraphState, currentTime: number, eventIndex: number) => void)[] = [];

  constructor() {}

  async loadTrace(url: string): Promise<void> {
    const res = await fetch(url);
    const text = await res.text();
    const lines = text.trim().split('\n');
    this.events = lines
      .map((l) => {
        try {
          return JSON.parse(l) as TraceEvent;
        } catch {
          return null;
        }
      })
      .filter((e): e is TraceEvent => e !== null);

    if (this.events.length > 0) {
      this.duration = Math.max(...this.events.map((e) => e.t));
    } else {
      this.duration = 0;
    }
    this.currentTime = 0;
    this.isPlaying = false;
    this.notifyUpdate();
  }

  getEvents(): TraceEvent[] {
    return this.events;
  }

  getDuration(): number {
    return this.duration;
  }

  getCurrentTime(): number {
    return this.currentTime;
  }

  getIsPlaying(): boolean {
    return this.isPlaying;
  }

  getSpeed(): number {
    return this.speed;
  }

  setSpeed(speed: number): void {
    this.speed = speed;
  }

  getMaxNodeCount(): number {
    const nodeIds = new Set<string>();
    nodeIds.add('host');
    for (const e of this.events) {
      if (e.src === 'controller' || e.kind === 'ctl.step') {
        nodeIds.add('control-plane');
      }
      if (e.id) {
        nodeIds.add(e.id);
      }
    }
    return nodeIds.size;
  }

  play(): void {
    if (this.isPlaying) return;
    this.isPlaying = true;
    this.lastRafTime = performance.now();
    this.tick();
  }

  pause(): void {
    this.isPlaying = false;
  }

  seek(timeInSeconds: number): void {
    this.currentTime = Math.max(0, Math.min(timeInSeconds, this.duration));
    this.notifyUpdate();
  }

  onUpdate(cb: (state: GraphState, currentTime: number, eventIndex: number) => void): void {
    this.onUpdateCallbacks.push(cb);
  }

  private tick = (): void => {
    if (!this.isPlaying) return;
    const now = performance.now();
    const deltaSeconds = ((now - this.lastRafTime) / 1000) * this.speed;
    this.lastRafTime = now;

    this.currentTime += deltaSeconds;
    if (this.currentTime >= this.duration) {
      this.currentTime = this.duration;
      this.isPlaying = false;
      this.notifyUpdate();
      return;
    }

    this.notifyUpdate();
    requestAnimationFrame(this.tick);
  };

  private notifyUpdate(): void {
    const { state, eventIndex } = this.computeStateAt(this.currentTime);
    for (const cb of this.onUpdateCallbacks) {
      cb(state, this.currentTime, eventIndex);
    }
  }

  computeStateAt(timeSeconds: number): { state: GraphState; eventIndex: number } {
    const nodeMap = new Map<string, GraphNode>();
    const edgeMap = new Map<string, GraphEdge>();
    let activePulseEdge: GraphEdge | undefined;
    let activeNodeId: string | undefined;

    // Anchor: host node
    nodeMap.set('host', {
      id: 'host',
      label: 'Mac Host (Orchestrator)',
      role: 'host',
      phase: 'Running',
      color: '#38bdf8', // sky blue
      val: 22,
    });

    let eventIndex = -1;
    for (let i = 0; i < this.events.length; i++) {
      const e = this.events[i];
      if (e.t > timeSeconds) break;
      eventIndex = i;

      const isRecent = Math.abs(timeSeconds - e.t) < 1.5;

      // Check if control-plane activity exists
      if (e.src === 'controller' || e.kind === 'ctl.step') {
        if (!nodeMap.has('control-plane')) {
          nodeMap.set('control-plane', {
            id: 'control-plane',
            label: 'AX Control (ate-local)',
            role: 'control',
            phase: 'Running',
            color: '#a855f7', // purple
            val: 18,
          });
          edgeMap.set('host-cp', {
            id: 'host-cp',
            source: 'host',
            target: 'control-plane',
            kind: 'control',
            label: 'gRPC Control',
          });
        }
        if (isRecent) {
          activeNodeId = 'control-plane';
        }
      }

      if (e.kind === 'node.add' && e.id) {
        nodeMap.set(e.id, {
          id: e.id,
          label: e.label || e.id,
          role: e.role || 'worker',
          phase: 'Pending',
          color: '#eab308', // yellow
          val: 14,
        });
        edgeMap.set(`host-${e.id}`, {
          id: `host-${e.id}`,
          source: 'host',
          target: e.id,
          kind: 'spawn',
          label: 'spawn',
        });
        if (isRecent) activeNodeId = e.id;
      } else if (e.kind === 'node.phase' && e.id && nodeMap.has(e.id)) {
        const n = nodeMap.get(e.id)!;
        n.phase = e.phase || n.phase;
        if (e.workerIP) n.workerIP = e.workerIP;
        if (n.phase === 'Running') {
          n.color = '#22c55e'; // green
        } else if (n.phase === 'Suspended') {
          n.color = '#f97316'; // orange
        } else if (n.phase === 'Failed') {
          n.color = '#ef4444'; // red
        }
        if (isRecent) activeNodeId = e.id;
      } else if (e.kind === 'node.ready' && e.id && nodeMap.has(e.id)) {
        const n = nodeMap.get(e.id)!;
        n.phase = 'Running';
        n.color = '#22c55e'; // green
        if (e.workerIP) n.workerIP = e.workerIP;
        if (isRecent) activeNodeId = e.id;
      } else if (e.kind === 'node.remove' && e.id) {
        nodeMap.delete(e.id);
        edgeMap.delete(`host-${e.id}`);
      } else if (e.kind === 'edge.msg' && e.from && e.to) {
        const edgeId = `msg-${e.from}-${e.to}`;
        const edge: GraphEdge = {
          id: edgeId,
          source: e.from,
          target: e.to,
          kind: 'msg',
          label: e.label || 'msg',
          active: isRecent,
        };
        edgeMap.set(edgeId, edge);
        if (isRecent) {
          activePulseEdge = edge;
          activeNodeId = e.to;
        }
      }
    }

    return {
      state: {
        nodes: Array.from(nodeMap.values()),
        edges: Array.from(edgeMap.values()),
        activePulseEdge,
        activeNodeId,
      },
      eventIndex,
    };
  }
}
