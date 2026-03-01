/**
 * Main entry point for the Godot Project Map Visualizer
 */

import {
  nodes, edges, camera, NODE_W, NODE_H,
  setCircularDeps, setOrphanedScripts
} from './state.js';
import { connectWebSocket } from './websocket.js';
import { initLayout } from './layout.js';
import { initCanvas, resize, draw, updateZoomIndicator, fitToView } from './canvas.js';
import { initPanel } from './panel.js';
import { initModals } from './modals.js';
import { initEvents, updateStats } from './events.js';
import './usages.js'; // Load usages module for side effects (global functions)

// Initialize everything when DOM is ready
function init() {
  // Connect WebSocket for real-time communication
  connectWebSocket();

  // Initialize canvas and rendering (also restores saved positions)
  const { positionsRestored } = initCanvas();

  // Get zoom indicator element
  const zoomIndicator = document.getElementById('zoom-indicator');

  if (nodes.length === 0) {
    // No scripts found - show placeholder
    const ctx = document.getElementById('canvas').getContext('2d');
    const W = window.innerWidth;
    const H = window.innerHeight;

    ctx.font = '18px -apple-system, system-ui, sans-serif';
    ctx.fillStyle = '#706c66';
    ctx.textAlign = 'center';
    ctx.fillText('No scripts found in project', W / 2, H / 2);
    zoomIndicator.style.display = 'none';
  } else {
    if (positionsRestored) {
      updateZoomIndicator();
    } else {
      initLayout();
      fitToView(nodes);
    }
  }

  // Run dependency analysis
  analyzeDependencies();

  // Initialize panel, modals, and event handlers after layout + folder groups are ready
  initPanel();
  initModals();
  initEvents();
  updateStats();

  // Initial draw — everything is ready
  if (nodes.length > 0) {
    draw();
  }
}

// Dependency analysis: detect circular deps and orphaned scripts
function analyzeDependencies() {
  if (nodes.length === 0) return;

  // Build adjacency list from edges (only extends/preload — structural deps)
  const adj = {};
  const hasIncoming = new Set();
  const hasOutgoing = new Set();

  for (const n of nodes) adj[n.path] = [];

  for (const e of edges) {
    if (e.type === 'extends' || e.type === 'preload') {
      if (adj[e.from]) {
        adj[e.from].push(e.to);
        hasOutgoing.add(e.from);
        hasIncoming.add(e.to);
      }
    }
  }

  // Detect cycles using DFS with coloring (white/gray/black)
  const WHITE = 0, GRAY = 1, BLACK = 2;
  const color = {};
  const parent = {};
  const cycles = [];

  for (const path of Object.keys(adj)) color[path] = WHITE;

  function dfs(u) {
    color[u] = GRAY;
    for (const v of adj[u]) {
      if (color[v] === undefined) continue; // Not a known node
      if (color[v] === GRAY) {
        // Found a cycle — trace back
        const cycle = [v, u];
        let cur = u;
        while (parent[cur] && parent[cur] !== v) {
          cur = parent[cur];
          cycle.push(cur);
        }
        cycles.push(cycle);
      } else if (color[v] === WHITE) {
        parent[v] = u;
        dfs(v);
      }
    }
    color[u] = BLACK;
  }

  for (const path of Object.keys(adj)) {
    if (color[path] === WHITE) dfs(path);
  }

  // Mark nodes that participate in cycles
  const inCycle = new Set();
  for (const cycle of cycles) {
    for (const path of cycle) inCycle.add(path);
  }

  // Find orphaned scripts (no incoming AND no outgoing structural edges)
  const orphaned = [];
  for (const n of nodes) {
    if (!hasIncoming.has(n.path) && !hasOutgoing.has(n.path)) {
      orphaned.push(n.path);
    }
  }

  // Tag nodes
  for (const n of nodes) {
    n._inCycle = inCycle.has(n.path);
    n._orphaned = orphaned.includes(n.path);
  }

  setCircularDeps(cycles);
  setOrphanedScripts(orphaned);
}

// Start when DOM is loaded
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
