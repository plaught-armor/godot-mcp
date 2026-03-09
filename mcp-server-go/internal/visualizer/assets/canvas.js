/**
 * Canvas rendering, camera controls, and drawing utilities
 */

import {
  nodes, edges, NODE_W, NODE_H, camera, defaultZoom,
  W, H, setDimensions, searchTerm, hoveredNode, selectedNode,
  currentView, sceneData, expandedScene, expandedSceneHierarchy,
  selectedSceneNode, hoveredSceneNode, scenePositions,
  setExpandedScene, setSelectedSceneNode, setHoveredSceneNode,
  setScenePosition, scriptToScenes,
  MINIMAP_W, MINIMAP_H, MINIMAP_MARGIN, MINIMAP_PADDING,
  folderGroups, setFolderGroups,
  rootFolderGroups, setRootFolderGroups, getRootFolder,
  connectionDrag
} from './state.js';

let canvas, ctx;
let zoomIndicator, zoomText;
let dpr = 1; // Device pixel ratio

// Storage key for position persistence
const STORAGE_KEY = 'godot-visualizer-positions';

export function initCanvas() {
  canvas = document.getElementById('canvas');
  ctx = canvas.getContext('2d');
  zoomIndicator = document.getElementById('zoom-indicator');
  zoomText = document.getElementById('zoom-text');

  // Get device pixel ratio for crisp rendering on high-DPI displays
  dpr = window.devicePixelRatio || 1;

  resize();
  const positionsRestored = loadPositions(); // Restore saved positions
  return { canvas, ctx, positionsRestored };
}

export function getCanvas() {
  return canvas;
}

export function resize() {
  const w = window.innerWidth;
  const h = window.innerHeight;
  setDimensions(w, h);

  // Update DPR in case it changed (e.g., moving window between displays)
  dpr = window.devicePixelRatio || 1;

  // Set canvas size accounting for device pixel ratio for crisp rendering
  canvas.width = w * dpr;
  canvas.height = h * dpr;

  // Scale canvas back to CSS size
  canvas.style.width = w + 'px';
  canvas.style.height = h + 'px';

  // Scale context to account for DPR
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}

export function screenToWorld(sx, sy) {
  return {
    x: (sx - W / 2) / camera.zoom + camera.x,
    y: (sy - H / 2) / camera.zoom + camera.y
  };
}

export function updateZoomIndicator() {
  const pct = Math.round(camera.zoom * 100);
  zoomText.value = pct + '%';
  zoomIndicator.classList.toggle('faded', Math.abs(camera.zoom - defaultZoom) < 0.01);
}

export function resetZoom() {
  camera.zoom = defaultZoom;
  updateZoomIndicator();
  draw();
}

export function setCustomZoom(value) {
  // Parse percentage string like "150%" or just "150" or "1.5"
  let parsed = parseFloat(value.replace('%', '').trim());
  if (isNaN(parsed)) return;
  
  // If user entered a small number like 1.5, treat as multiplier
  if (parsed > 0 && parsed < 10) {
    parsed = parsed * 100;
  }
  
  // Clamp to valid range (10% - 500%)
  const newZoom = Math.max(0.1, Math.min(5, parsed / 100));
  camera.zoom = newZoom;
  updateZoomIndicator();
  draw();
}

// Make functions available globally for onclick
window.resetZoom = resetZoom;
window.setCustomZoom = setCustomZoom;

// ---- Position Persistence ----
export function savePositions() {
  try {
    const positions = {};
    nodes.forEach(n => {
      positions[n.path] = { x: n.x, y: n.y };
    });
    localStorage.setItem(STORAGE_KEY, JSON.stringify({
      positions,
      camera: { x: camera.x, y: camera.y, zoom: camera.zoom }
    }));
  } catch (e) {
    console.warn('Failed to save positions:', e);
  }
}

export function loadPositions() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (!saved) return false;

    const data = JSON.parse(saved);
    let restored = 0;

    if (data.positions) {
      nodes.forEach(n => {
        if (data.positions[n.path]) {
          n.x = data.positions[n.path].x;
          n.y = data.positions[n.path].y;
          restored++;
        }
      });
    }

    if (data.camera && restored > 0) {
      camera.x = data.camera.x;
      camera.y = data.camera.y;
      camera.zoom = data.camera.zoom;
      // Don't change defaultZoom - keep it at 1 (100%) so reset always goes to 100%
    }

    return restored > 0;
  } catch (e) {
    console.warn('Failed to load positions:', e);
    return false;
  }
}

export function clearPositions() {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch (e) {
    console.warn('Failed to clear positions:', e);
  }
}

// Save positions when node is moved
let folderGroupsDirty = true;

export function invalidateFolderGroups() {
  folderGroupsDirty = true;
}

export function onNodeMoved() {
  folderGroupsDirty = true;
  savePositions();
  draw();
}

// ---- Folder Groups ----
export function computeFolderGroups() {
  if (!folderGroupsDirty) return;
  folderGroupsDirty = false;
  // Subfolder groups (colored)
  const groups = {};
  for (const n of nodes) {
    if (!n.folder) continue;
    if (!groups[n.folder]) groups[n.folder] = { nodes: [], color: n.color };
    groups[n.folder].nodes.push(n);
  }
  for (const folder of Object.keys(groups)) {
    if (groups[folder].nodes.length < 2) {
      delete groups[folder];
      continue;
    }
    const group = groups[folder];
    const pad = 30, labelH = 24;
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const n of group.nodes) {
      minX = Math.min(minX, n.x - NODE_W / 2);
      maxX = Math.max(maxX, n.x + NODE_W / 2);
      minY = Math.min(minY, n.y - NODE_H / 2);
      maxY = Math.max(maxY, n.y + NODE_H / 2);
    }
    group.bounds = {
      x: minX - pad,
      y: minY - pad - labelH,
      w: (maxX - minX) + pad * 2,
      h: (maxY - minY) + pad * 2 + labelH
    };
    group.label = folder;
  }
  setFolderGroups(groups);

  // Root folder groups (grey) — encompass all subfolders sharing the same root
  const rootGroups = {};
  for (const n of nodes) {
    const root = getRootFolder(n.folder);
    if (!root) continue;
    if (!rootGroups[root]) rootGroups[root] = { nodes: [] };
    rootGroups[root].nodes.push(n);
  }
  for (const root of Object.keys(rootGroups)) {
    // Only show root group if it contains nodes from 2+ different subfolders
    const subfolders = new Set(rootGroups[root].nodes.map(n => n.folder));
    if (subfolders.size < 2) {
      delete rootGroups[root];
      continue;
    }
    const group = rootGroups[root];
    const pad = 50, labelH = 28;
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const n of group.nodes) {
      minX = Math.min(minX, n.x - NODE_W / 2);
      maxX = Math.max(maxX, n.x + NODE_W / 2);
      minY = Math.min(minY, n.y - NODE_H / 2);
      maxY = Math.max(maxY, n.y + NODE_H / 2);
    }
    group.bounds = {
      x: minX - pad,
      y: minY - pad - labelH,
      w: (maxX - minX) + pad * 2,
      h: (maxY - minY) + pad * 2 + labelH
    };
    group.label = root;
    group.color = '#888888'; // Grey for root folders
  }
  setRootFolderGroups(rootGroups);
}

// ---- Drawing ----
export function draw() {
  if (currentView === 'scenes') {
    drawSceneView();
    return;
  }

  // Recompute folder groups every draw (cheap single pass over nodes)
  computeFolderGroups();

  // Ensure DPR transform is set for crisp rendering on high-DPI displays
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  
  // Disable image smoothing for crisper shapes and lines
  ctx.imageSmoothingEnabled = false;
  
  // Use crisp line rendering
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  
  ctx.clearRect(0, 0, W, H);
  ctx.save();
  ctx.translate(Math.round(W / 2), Math.round(H / 2));
  ctx.scale(camera.zoom, camera.zoom);
  ctx.translate(-camera.x, -camera.y);

  // Draw folder group backgrounds (behind everything)
  drawFolderGroups();

  // Build path index for quick lookup
  const pathIdx = {};
  nodes.forEach((n, i) => pathIdx[n.path] = i);

  // Group edges by node pair, type, and direction for bundled drawing
  const edgeGroups = {};
  for (const e of edges) {
    const si = pathIdx[e.from], ti = pathIdx[e.to];
    if (si === undefined || ti === undefined) continue;

    // Keep direction (A->B is different from B->A)
    const key = `${si}-${ti}-${e.type}`;
    if (!edgeGroups[key]) {
      edgeGroups[key] = { from: e.from, to: e.to, type: e.type, edges: [], si, ti };
    }
    edgeGroups[key].edges.push(e);
  }

  // Draw bundled edges
  for (const key of Object.keys(edgeGroups)) {
    const group = edgeGroups[key];
    const s = nodes[group.si], t = nodes[group.ti];
    const count = group.edges.length;

    // Skip edges where both nodes are hidden during search
    if (searchTerm && s.visible === false && t.visible === false) continue;

    // Dim edges when one node is hidden, or when neither is highlighted
    const bothVisible = s.visible !== false && t.visible !== false;
    ctx.globalAlpha = (!bothVisible || (!s.highlighted && !t.highlighted)) ? 0.08 : 0.5;

    // Calculate perpendicular offset for multiple edge types between same nodes
    const angle = Math.atan2(t.y - s.y, t.x - s.x);
    const perpAngle = angle + Math.PI / 2;

    // Get offset based on edge type (so different types don't overlap)
    const typeOffset = group.type === 'extends' ? 0 : group.type === 'preload' ? 8 : 16;
    const offsetX = Math.cos(perpAngle) * typeOffset;
    const offsetY = Math.sin(perpAngle) * typeOffset;

    ctx.beginPath();
    ctx.moveTo(s.x + offsetX, s.y + offsetY);
    ctx.lineTo(t.x + offsetX, t.y + offsetY);

    // Line widths scale with zoom (fixed world-space size)
    if (group.type === 'extends') {
      ctx.strokeStyle = '#7aa2f7';
      ctx.setLineDash([]);
      ctx.lineWidth = 2;
    } else if (group.type === 'preload') {
      ctx.strokeStyle = '#d4a27f';
      ctx.setLineDash([]);
      ctx.lineWidth = 1.5;
    } else {
      ctx.strokeStyle = '#a6e3a1';
      ctx.setLineDash([4, 4]);
      ctx.lineWidth = 1.5;
    }
    ctx.stroke();
    ctx.setLineDash([]);

    // Arrow at midpoint - fixed world-space size
    const al = 10;
    const mx = (s.x + t.x) / 2 + offsetX, my = (s.y + t.y) / 2 + offsetY;
    ctx.beginPath();
    ctx.moveTo(mx + Math.cos(angle) * al, my + Math.sin(angle) * al);
    ctx.lineTo(mx + Math.cos(angle + 2.5) * al * 0.6, my + Math.sin(angle + 2.5) * al * 0.6);
    ctx.lineTo(mx + Math.cos(angle - 2.5) * al * 0.6, my + Math.sin(angle - 2.5) * al * 0.6);
    ctx.closePath();
    ctx.fillStyle = ctx.strokeStyle;
    ctx.fill();

    // Draw count badge if multiple connections of same type
    if (count > 1) {
      const badgeX = mx + Math.cos(perpAngle) * 12;
      const badgeY = my + Math.sin(perpAngle) * 12;
      const badgeSize = 16;

      ctx.globalAlpha = bothVisible ? 0.9 : 0.3;
      ctx.beginPath();
      ctx.arc(badgeX, badgeY, badgeSize / 2, 0, Math.PI * 2);
      ctx.fillStyle = ctx.strokeStyle;
      ctx.fill();

      // Count text - scales with zoom
      ctx.fillStyle = '#1a1a1e';
      ctx.font = `bold 10px -apple-system, system-ui, sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(count.toString(), badgeX, badgeY);
    }
  }

  ctx.globalAlpha = 1;

  // Draw nodes
  for (const n of nodes) {
    // Skip hidden nodes during search
    if (searchTerm && n.visible === false) continue;

    // Round coordinates for crisper rendering
    const x = Math.round(n.x - NODE_W / 2);
    const y = Math.round(n.y - NODE_H / 2);
    const isHovered = n === hoveredNode, isSelected = n === selectedNode;

    ctx.globalAlpha = n.highlighted ? 1 : 0.12;

    // Shadow - fixed world-space size
    ctx.shadowColor = 'rgba(0,0,0,0.4)';
    ctx.shadowBlur = isHovered ? 16 : 8;
    ctx.shadowOffsetY = 2;

    // Background
    ctx.beginPath();
    roundRect(ctx, x, y, NODE_W, NODE_H, 10);
    ctx.fillStyle = isSelected ? '#35353b' : isHovered ? '#303036' : '#242428';
    ctx.fill();

    ctx.shadowBlur = 0;
    ctx.shadowOffsetY = 0;

    // Border - fixed world-space width
    ctx.strokeStyle = isSelected ? n.color : isHovered ? n.color : '#3a3a40';
    ctx.lineWidth = isSelected ? 2 : 1;
    ctx.stroke();

    // Left accent bar
    ctx.beginPath();
    ctx.roundRect(x + 4, y + 8, 3, NODE_H - 16, 2);
    ctx.fillStyle = n.color;
    ctx.fill();

    // Title - scales with node (no zoom compensation)
    const titleSize = 14;
    ctx.font = `600 ${titleSize}px -apple-system, system-ui, sans-serif`;
    ctx.fillStyle = '#e8e4df';
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'left';
    const displayName = n.class_name || n.filename.replace('.gd', '');
    ctx.fillText(displayName, x + 16, y + NODE_H / 2 - 6);

    // Subtitle with colored stats - scales with node
    const subSize = 11;
    const varCount = n.variables ? n.variables.length : 0;
    const funcCount = n.functions ? n.functions.length : 0;
    const sigCount = n.signals ? n.signals.length : 0;

    // Draw subtitle parts with colors
    ctx.font = `${subSize}px -apple-system, system-ui, sans-serif`;
    const subY = y + NODE_H / 2 + 9;
    let subX = x + 16;

    // Extends
    ctx.fillStyle = '#706c66';
    const extendsText = (n.extends || 'Node') + ' · ';
    ctx.fillText(extendsText, subX, subY);
    subX += ctx.measureText(extendsText).width;

    // Functions (cyan/teal)
    ctx.fillStyle = '#89dceb';
    ctx.fillText(funcCount + 'f', subX, subY);
    subX += ctx.measureText(funcCount + 'f').width;

    // Space
    ctx.fillStyle = '#706c66';
    ctx.fillText(' ', subX, subY);
    subX += ctx.measureText(' ').width;

    // Variables (purple)
    ctx.fillStyle = '#cba6f7';
    ctx.fillText(varCount + 'v', subX, subY);
    subX += ctx.measureText(varCount + 'v').width;

    // Space
    ctx.fillStyle = '#706c66';
    ctx.fillText(' ', subX, subY);
    subX += ctx.measureText(' ').width;

    // Signals (green)
    ctx.fillStyle = '#a6e3a1';
    ctx.fillText(sigCount + 's', subX, subY);
    subX += ctx.measureText(sigCount + 's').width;

    // Separator
    ctx.fillStyle = '#706c66';
    ctx.fillText(' · ', subX, subY);
    subX += ctx.measureText(' · ').width;

    // Lines (yellow/amber)
    ctx.fillStyle = '#f9e2af';
    ctx.fillText(n.line_count + 'L', subX, subY);
    
    // Scene usage badge (top-right corner)
    const usedInScenes = scriptToScenes[n.path];
    if (usedInScenes && usedInScenes.length > 0) {
      const badgeX = x + NODE_W - 8;
      const badgeY = y + 8;

      ctx.fillStyle = 'rgba(166, 227, 161, 0.2)';
      ctx.beginPath();
      ctx.roundRect(badgeX - 20, badgeY - 4, 24, 14, 3);
      ctx.fill();

      ctx.fillStyle = '#a6e3a1';
      ctx.font = `600 9px -apple-system, system-ui, sans-serif`;
      ctx.textAlign = 'right';
      ctx.fillText('📦' + usedInScenes.length, badgeX, badgeY + 4);
      ctx.textAlign = 'left';
    }

    // Git status indicator (top-left corner, outside the node)
    if (n.gitStatus) {
      const gitColor = n.gitStatus === 'added' ? '#a6e3a1' :
                        n.gitStatus === 'modified' ? '#f9e2af' :
                        n.gitStatus === 'deleted' ? '#f38ba8' :
                        '#89dceb'; // renamed/other
      const dotR = 5;
      const dotX = x + dotR + 2;
      const dotY = y - dotR - 2;

      ctx.beginPath();
      ctx.arc(dotX, dotY, dotR, 0, Math.PI * 2);
      ctx.fillStyle = gitColor;
      ctx.fill();

      // Letter inside dot
      ctx.fillStyle = '#1a1a1e';
      ctx.font = `bold 7px -apple-system, system-ui, sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(n.gitStatus[0].toUpperCase(), dotX, dotY);
      ctx.textAlign = 'left';
      ctx.textBaseline = 'alphabetic';
    }

    // Dependency analysis: circular dep warning (bottom-right)
    if (n._inCycle) {
      const warnX = x + NODE_W - 6;
      const warnY = y + NODE_H - 6;
      ctx.fillStyle = '#f38ba8';
      ctx.font = `bold 10px -apple-system, system-ui, sans-serif`;
      ctx.textAlign = 'right';
      ctx.fillText('⟳', warnX, warnY);
      ctx.textAlign = 'left';
    }

    // Dependency analysis: orphaned script (dimmed border)
    if (n._orphaned) {
      ctx.strokeStyle = '#f9e2af44';
      ctx.lineWidth = 1;
      ctx.setLineDash([3, 3]);
      ctx.beginPath();
      roundRect(ctx, x, y, NODE_W, NODE_H, 10);
      ctx.stroke();
      ctx.setLineDash([]);
    }

    // Signal ports on right edge (shown on hover/selected, not during connection drag)
    if ((isHovered || isSelected) && !connectionDrag && n.signals && n.signals.length > 0) {
      drawSignalPorts(n, x, y);
    }
  }

  // Draw connection drag wire + function ports (in world space, before restore)
  if (connectionDrag) {
    drawConnectionWire();
  }

  ctx.globalAlpha = 1;
  ctx.restore();

  // Draw minimap (in screen space, after restore)
  drawMinimap();
}

// ---- Folder Group Drawing ----
function drawFolderGroups() {
  // Draw root folder backgrounds first (grey, behind everything)
  if (rootFolderGroups && Object.keys(rootFolderGroups).length > 0) {
    for (const group of Object.values(rootFolderGroups)) {
      if (!group.bounds) continue;
      const { x, y, w, h } = group.bounds;

      // Grey background fill (very subtle)
      ctx.beginPath();
      ctx.roundRect(x, y, w, h, 16);
      ctx.fillStyle = 'rgba(136, 136, 136, 0.04)';
      ctx.fill();

      // Grey border
      ctx.strokeStyle = 'rgba(136, 136, 136, 0.15)';
      ctx.lineWidth = 1;
      ctx.stroke();

      // Root folder label
      ctx.font = '600 13px -apple-system, system-ui, sans-serif';
      ctx.fillStyle = 'rgba(136, 136, 136, 0.5)';
      ctx.textAlign = 'left';
      ctx.textBaseline = 'top';
      ctx.fillText(group.label, x + 14, y + 8);
    }
  }

  // Draw subfolder backgrounds on top (colored)
  if (folderGroups && Object.keys(folderGroups).length > 0) {
    for (const group of Object.values(folderGroups)) {
      if (!group.bounds) continue;
      const { x, y, w, h } = group.bounds;
      const color = group.color;

      // Background fill (very low opacity)
      ctx.beginPath();
      ctx.roundRect(x, y, w, h, 12);
      ctx.fillStyle = color + '0D'; // ~5% opacity
      ctx.fill();

      // Border
      ctx.strokeStyle = color + '33'; // ~20% opacity
      ctx.lineWidth = 1;
      ctx.stroke();

      // Folder label
      ctx.font = '600 12px -apple-system, system-ui, sans-serif';
      ctx.fillStyle = color + '99'; // ~60% opacity
      ctx.textAlign = 'left';
      ctx.textBaseline = 'top';
      ctx.fillText(group.label, x + 10, y + 6);
    }
  }

  ctx.textAlign = 'left';
  ctx.textBaseline = 'alphabetic';
}

// ---- Signal Ports on Node Edge (hover) ----

const SIG_PORT_R = 5; // radius of signal port dot
const SIG_PORT_GAP = 4;

function drawSignalPorts(node, nodeX, nodeY) {
  const sigs = node.signals;
  const count = sigs.length;
  const totalH = count * (SIG_PORT_R * 2 + SIG_PORT_GAP) - SIG_PORT_GAP;
  const startY = nodeY + NODE_H / 2 - totalH / 2;
  const portX = nodeX + NODE_W + SIG_PORT_R + 3;

  for (let i = 0; i < count; i++) {
    const py = startY + i * (SIG_PORT_R * 2 + SIG_PORT_GAP) + SIG_PORT_R;
    const sig = sigs[i];
    const sigName = typeof sig === 'string' ? sig : sig.name;

    // Dot
    ctx.beginPath();
    ctx.arc(portX, py, SIG_PORT_R, 0, Math.PI * 2);
    ctx.fillStyle = '#a6e3a1';
    ctx.fill();
    ctx.strokeStyle = '#1a1a1e';
    ctx.lineWidth = 1;
    ctx.stroke();

    // Label
    ctx.font = '9px -apple-system, system-ui, sans-serif';
    ctx.fillStyle = '#a6e3a1';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText(sigName.length > 14 ? sigName.slice(0, 13) + '…' : sigName, portX + SIG_PORT_R + 4, py);
  }
}

// Hit test signal ports on a hovered/selected node. Returns { index, signalName } or null.
export function signalPortHitTest(wx, wy, node) {
  if (!node || !node.signals || node.signals.length === 0) return null;
  const count = node.signals.length;
  const nodeX = node.x - NODE_W / 2;
  const nodeY = node.y - NODE_H / 2;
  const totalH = count * (SIG_PORT_R * 2 + SIG_PORT_GAP) - SIG_PORT_GAP;
  const startY = nodeY + NODE_H / 2 - totalH / 2;
  const portX = nodeX + NODE_W + SIG_PORT_R + 3;

  for (let i = 0; i < count; i++) {
    const py = startY + i * (SIG_PORT_R * 2 + SIG_PORT_GAP) + SIG_PORT_R;
    const dx = wx - portX, dy = wy - py;
    if (dx * dx + dy * dy <= (SIG_PORT_R + 3) * (SIG_PORT_R + 3)) {
      const sig = node.signals[i];
      return { index: i, signalName: typeof sig === 'string' ? sig : sig.name, signalParams: typeof sig === 'object' ? sig.params || '' : '' };
    }
  }
  return null;
}

// ---- Connection Drag Wire + Function Ports ----

const PORT_H = 16;
const PORT_GAP = 2;
const PORT_W = 110;
const PORT_OFFSET = 8; // gap between ports and node edge

function drawConnectionWire() {
  const drag = connectionDrag;
  if (!drag) return;

  const src = drag.sourceNode;
  // Source: right edge center of source node
  const srcX = src.x + NODE_W / 2;
  const srcY = src.y;

  // Cursor in world coords
  const cursor = screenToWorld(drag.cursorX, drag.cursorY);
  let endX = cursor.x, endY = cursor.y;

  // If hovering a target node, snap to its left edge
  if (drag.targetNode) {
    endX = drag.targetNode.x - NODE_W / 2;
    endY = drag.targetNode.y;
  }

  // Draw dashed green wire
  ctx.save();
  ctx.strokeStyle = '#a6e3a1';
  ctx.lineWidth = 2;
  ctx.setLineDash([6, 4]);
  ctx.globalAlpha = 0.8;
  ctx.beginPath();
  // Bezier curve for a nice arc
  const cpOffset = Math.min(80, Math.abs(endX - srcX) * 0.4);
  ctx.moveTo(srcX, srcY);
  ctx.bezierCurveTo(srcX + cpOffset, srcY, endX - cpOffset, endY, endX, endY);
  ctx.stroke();
  ctx.setLineDash([]);

  // Draw small circle at source
  ctx.beginPath();
  ctx.arc(srcX, srcY, 4, 0, Math.PI * 2);
  ctx.fillStyle = '#a6e3a1';
  ctx.fill();

  // Draw function ports on target node (if any)
  if (drag.targetNode && drag.targetNode.functions && drag.targetNode.functions.length > 0) {
    drawFunctionPorts(drag.targetNode, drag.hoveredPort);
  }

  // Highlight all valid target nodes (those with functions)
  for (const n of nodes) {
    if (n === src) continue;
    if (!n.functions || n.functions.length === 0) continue;
    if (n === drag.targetNode) continue; // already highlighted via ports
    if (searchTerm && n.visible === false) continue;

    // Subtle glow on valid targets
    ctx.strokeStyle = '#a6e3a166';
    ctx.lineWidth = 1;
    ctx.beginPath();
    roundRect(ctx, n.x - NODE_W / 2 - 2, n.y - NODE_H / 2 - 2, NODE_W + 4, NODE_H + 4, 12);
    ctx.stroke();
  }

  ctx.restore();
}

function drawFunctionPorts(node, hoveredIdx) {
  const funcs = node.functions;
  const count = funcs.length;
  const totalH = count * PORT_H + (count - 1) * PORT_GAP;
  const startY = node.y - totalH / 2;
  const portX = node.x - NODE_W / 2 - PORT_W - PORT_OFFSET;

  for (let i = 0; i < count; i++) {
    const py = startY + i * (PORT_H + PORT_GAP);
    const isHovered = i === hoveredIdx;

    // Port background
    ctx.beginPath();
    ctx.roundRect(portX, py, PORT_W, PORT_H, 4);
    ctx.fillStyle = isHovered ? 'rgba(166, 227, 161, 0.25)' : 'rgba(36, 36, 40, 0.9)';
    ctx.fill();
    ctx.strokeStyle = isHovered ? '#a6e3a1' : '#3a3a40';
    ctx.lineWidth = 1;
    ctx.stroke();

    // Function name
    ctx.font = '9px -apple-system, system-ui, sans-serif';
    ctx.fillStyle = isHovered ? '#a6e3a1' : '#9a9a9a';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    const label = funcs[i].name;
    ctx.fillText(label.length > 16 ? label.slice(0, 15) + '…' : label, portX + 6, py + PORT_H / 2);

    // Connection dot on right edge of port
    ctx.beginPath();
    ctx.arc(portX + PORT_W, py + PORT_H / 2, 3, 0, Math.PI * 2);
    ctx.fillStyle = isHovered ? '#a6e3a1' : '#5a5a60';
    ctx.fill();
  }

  // Draw connecting line from ports to node
  ctx.beginPath();
  ctx.moveTo(portX + PORT_W, startY + PORT_H / 2);
  ctx.lineTo(node.x - NODE_W / 2, node.y);
  ctx.strokeStyle = '#3a3a40';
  ctx.lineWidth = 1;
  ctx.stroke();
  if (count > 1) {
    ctx.beginPath();
    ctx.moveTo(portX + PORT_W, startY + (count - 1) * (PORT_H + PORT_GAP) + PORT_H / 2);
    ctx.lineTo(node.x - NODE_W / 2, node.y);
    ctx.stroke();
  }
}

export function portHitTest(wx, wy, node) {
  if (!node || !node.functions || node.functions.length === 0) return -1;
  const count = node.functions.length;
  const totalH = count * PORT_H + (count - 1) * PORT_GAP;
  const startY = node.y - totalH / 2;
  const portX = node.x - NODE_W / 2 - PORT_W - PORT_OFFSET;

  for (let i = 0; i < count; i++) {
    const py = startY + i * (PORT_H + PORT_GAP);
    if (wx >= portX && wx <= portX + PORT_W && wy >= py && wy <= py + PORT_H) {
      return i;
    }
  }
  return -1;
}

// ---- Minimap ----
let mmRect = null;       // { x, y, w, h } screen coords
let mmWorldBounds = null; // { minX, minY, w, h }
let mmScale = 0;
let mmContentOffset = null; // { x, y }

export function getMinimapState() {
  return { rect: mmRect, worldBounds: mmWorldBounds, scale: mmScale, contentOffset: mmContentOffset };
}

function drawMinimap() {
  if (nodes.length === 0 || currentView !== 'scripts') return;

  // Compute world bounding box
  let wMinX = Infinity, wMaxX = -Infinity, wMinY = Infinity, wMaxY = -Infinity;
  for (const n of nodes) {
    wMinX = Math.min(wMinX, n.x - NODE_W / 2);
    wMaxX = Math.max(wMaxX, n.x + NODE_W / 2);
    wMinY = Math.min(wMinY, n.y - NODE_H / 2);
    wMaxY = Math.max(wMaxY, n.y + NODE_H / 2);
  }
  const worldPad = 50;
  wMinX -= worldPad; wMaxX += worldPad;
  wMinY -= worldPad; wMaxY += worldPad;
  const worldW = wMaxX - wMinX;
  const worldH = wMaxY - wMinY;

  // Minimap position (bottom-right)
  const mmX = W - MINIMAP_W - MINIMAP_MARGIN;
  const mmY = H - MINIMAP_H - MINIMAP_MARGIN;

  // Scale factor (fit world into minimap with padding)
  const scaleX = (MINIMAP_W - 2 * MINIMAP_PADDING) / worldW;
  const scaleY = (MINIMAP_H - 2 * MINIMAP_PADDING) / worldH;
  const scale = Math.min(scaleX, scaleY);

  // Center content within minimap
  const contentW = worldW * scale;
  const contentH = worldH * scale;
  const offX = mmX + (MINIMAP_W - contentW) / 2;
  const offY = mmY + (MINIMAP_H - contentH) / 2;

  // Store for event hit testing
  mmRect = { x: mmX, y: mmY, w: MINIMAP_W, h: MINIMAP_H };
  mmWorldBounds = { minX: wMinX, minY: wMinY, w: worldW, h: worldH };
  mmScale = scale;
  mmContentOffset = { x: offX, y: offY };

  // Re-apply DPR transform (we're in screen space after ctx.restore())
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  ctx.save();

  // Background
  ctx.globalAlpha = 0.85;
  ctx.fillStyle = '#1a1a1e';
  ctx.beginPath();
  ctx.roundRect(mmX, mmY, MINIMAP_W, MINIMAP_H, 8);
  ctx.fill();
  ctx.strokeStyle = '#3a3a40';
  ctx.lineWidth = 1;
  ctx.stroke();
  ctx.globalAlpha = 1;

  // Clip to minimap
  ctx.beginPath();
  ctx.roundRect(mmX + 1, mmY + 1, MINIMAP_W - 2, MINIMAP_H - 2, 7);
  ctx.clip();

  // Draw nodes as small colored rects
  for (const n of nodes) {
    if (searchTerm && n.visible === false) continue;
    const dotX = offX + (n.x - wMinX) * scale;
    const dotY = offY + (n.y - wMinY) * scale;
    const dotW = Math.max(3, NODE_W * scale);
    const dotH = Math.max(2, NODE_H * scale);
    ctx.fillStyle = n.color;
    ctx.globalAlpha = n.highlighted ? 0.8 : 0.2;
    ctx.fillRect(dotX - dotW / 2, dotY - dotH / 2, dotW, dotH);
  }

  // Viewport rectangle
  const viewLeft = camera.x - (W / 2) / camera.zoom;
  const viewTop = camera.y - (H / 2) / camera.zoom;
  const viewW = W / camera.zoom;
  const viewH = H / camera.zoom;

  const vpX = offX + (viewLeft - wMinX) * scale;
  const vpY = offY + (viewTop - wMinY) * scale;
  const vpW = viewW * scale;
  const vpH = viewH * scale;

  ctx.globalAlpha = 1;
  ctx.strokeStyle = '#d4a27f';
  ctx.lineWidth = 1.5;
  ctx.strokeRect(vpX, vpY, vpW, vpH);
  ctx.fillStyle = '#d4a27f11';
  ctx.fillRect(vpX, vpY, vpW, vpH);

  ctx.restore();
}

// Scene view constants
const SCENE_CARD_W = 200;  // Match NODE_W
const SCENE_CARD_H = 54;   // Match NODE_H
const SCENE_NODE_MIN_W = 80;   // Minimum node width
const SCENE_NODE_MAX_W = 200;  // Maximum node width
const SCENE_NODE_H = 36;
const SCENE_NODE_GAP_X = 15;  // Reduced for tighter layout
const SCENE_NODE_GAP_Y = 40;

// Calculate dynamic node width based on name
function calculateNodeWidth(name) {
  // Approximate width: ~7px per character + padding
  const textWidth = (name || 'Node').length * 7;
  const padding = 35; // For script icon and margins
  return Math.min(SCENE_NODE_MAX_W, Math.max(SCENE_NODE_MIN_W, textWidth + padding));
}

function drawSceneView() {
  // Ensure DPR transform is set for crisp rendering on high-DPI displays
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  
  // Disable image smoothing for crisper shapes and lines
  ctx.imageSmoothingEnabled = false;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  
  ctx.clearRect(0, 0, W, H);
  ctx.save();
  ctx.translate(Math.round(W / 2), Math.round(H / 2));
  ctx.scale(camera.zoom, camera.zoom);
  ctx.translate(-camera.x, -camera.y);

  if (!sceneData || !sceneData.scenes || sceneData.scenes.length === 0) {
    drawSceneViewPlaceholder();
    ctx.restore();
    return;
  }

  // Check if we're in expanded mode
  if (expandedScene && expandedSceneHierarchy) {
    drawExpandedSceneView();
  } else {
    drawSceneOverview();
  }

  ctx.restore();
}

function drawSceneOverview() {
  const scenes = sceneData.scenes;
  
  // Calculate positions if not set
  scenes.forEach((scene, i) => {
    if (!scenePositions[scene.path]) {
      const cols = Math.max(1, Math.floor(Math.sqrt(scenes.length * 1.5)));
      setScenePosition(
        scene.path,
        (i % cols) * (SCENE_CARD_W + 40) - ((cols - 1) * (SCENE_CARD_W + 40)) / 2,
        Math.floor(i / cols) * (SCENE_CARD_H + 30) - 100
      );
    }
  });

  // Draw edges between scenes (instance relationships)
  if (sceneData.edges) {
    ctx.globalAlpha = 0.4;
    for (const edge of sceneData.edges) {
      const fromScene = scenes.find(s => s.path === edge.from);
      const toScene = scenes.find(s => s.path === edge.to);
      if (!fromScene || !toScene) continue;

      const fromPos = scenePositions[edge.from];
      const toPos = scenePositions[edge.to];
      if (!fromPos || !toPos) continue;

      const fromX = fromPos.x + SCENE_CARD_W / 2;
      const fromY = fromPos.y + SCENE_CARD_H;
      const toX = toPos.x + SCENE_CARD_W / 2;
      const toY = toPos.y;

      ctx.beginPath();
      ctx.moveTo(fromX, fromY);
      ctx.lineTo(toX, toY);
      ctx.strokeStyle = '#89dceb';
      ctx.lineWidth = 1.5;
      ctx.setLineDash([4, 4]);
      ctx.stroke();
      ctx.setLineDash([]);
    }
    ctx.globalAlpha = 1;
  }

  // Draw scene cards
  scenes.forEach((scene, i) => {
    const pos = scenePositions[scene.path];
    const x = pos.x;
    const y = pos.y;
    
    const isHovered = hoveredSceneNode && hoveredSceneNode.scenePath === scene.path && !hoveredSceneNode.nodePath;
    const isExpanded = expandedScene === scene.path;
    const sceneColor = getSceneColor(scene.path);

    // Shadow - match script node styling
    ctx.shadowColor = 'rgba(0,0,0,0.4)';
    ctx.shadowBlur = isHovered ? 16 : 8;
    ctx.shadowOffsetY = 2;

    // Scene card background - match script node colors
    ctx.beginPath();
    roundRect(ctx, x, y, SCENE_CARD_W, SCENE_CARD_H, 10);
    ctx.fillStyle = isExpanded ? '#35353b' : isHovered ? '#303036' : '#242428';
    ctx.fill();

    ctx.shadowBlur = 0;
    ctx.shadowOffsetY = 0;

    // Border - match script node styling
    ctx.strokeStyle = isExpanded ? sceneColor : isHovered ? sceneColor : '#3a3a40';
    ctx.lineWidth = isExpanded ? 2 : 1;
    ctx.stroke();

    // Left accent bar (scene color)
    ctx.beginPath();
    ctx.roundRect(x + 4, y + 8, 3, SCENE_CARD_H - 16, 2);
    ctx.fillStyle = sceneColor;
    ctx.fill();

    // Scene name (main label)
    ctx.fillStyle = '#e8e4df';
    ctx.font = `600 13px -apple-system, system-ui, sans-serif`;
    ctx.textAlign = 'left';
    const sceneName = scene.name || scene.path.split('/').pop().replace('.tscn', '');
    ctx.fillText(sceneName, x + 14, y + 22);

    // Root type and stats on second line
    const nodeCount = scene.node_count || (scene.nodes ? scene.nodes.length : 0);
    ctx.fillStyle = '#706c66';
    ctx.font = `11px -apple-system, system-ui, sans-serif`;
    ctx.fillText(`${scene.root_type || 'Node'} · ${nodeCount} nodes`, x + 14, y + 40);
  });
}

function drawExpandedSceneView() {
  const hierarchy = expandedSceneHierarchy;
  if (!hierarchy) return;

  // Draw back button area (handled by HTML overlay)
  
  // Draw the node tree
  const treeLayout = calculateTreeLayout(hierarchy);
  
  // Draw connection lines first
  drawTreeConnections(treeLayout.nodes);
  
  // Draw nodes
  for (const node of treeLayout.nodes) {
    drawSceneNode(node);
  }
}

function calculateTreeLayout(hierarchy) {
  const nodes = [];
  const LEVEL_HEIGHT = SCENE_NODE_H + SCENE_NODE_GAP_Y;
  
  // Simple layout: each node positions its children directly below,
  // centered on itself, without considering grandchildren widths
  function processNode(node, depth, centerX) {
    const nodeWidth = calculateNodeWidth(node.name);
    const x = centerX - nodeWidth / 2;
    const y = depth * LEVEL_HEIGHT;
    
    const nodeLayout = {
      ...node,
      x,
      y,
      width: nodeWidth,
      height: SCENE_NODE_H,
      childPositions: []
    };
    nodes.push(nodeLayout);

    // Layout children centered under this node
    if (node.children && node.children.length > 0) {
      // Calculate total width of direct children only
      let totalChildrenWidth = 0;
      for (const child of node.children) {
        totalChildrenWidth += calculateNodeWidth(child.name) + SCENE_NODE_GAP_X;
      }
      totalChildrenWidth -= SCENE_NODE_GAP_X; // Remove last gap
      
      // Start children centered under parent
      let childX = centerX - totalChildrenWidth / 2;
      
      for (const child of node.children) {
        const childWidth = calculateNodeWidth(child.name);
        const childCenterX = childX + childWidth / 2;
        
        nodeLayout.childPositions.push({
          x: childCenterX,
          y: (depth + 1) * LEVEL_HEIGHT
        });
        
        processNode(child, depth + 1, childCenterX);
        childX += childWidth + SCENE_NODE_GAP_X;
      }
    }

    return nodeLayout;
  }

  processNode(hierarchy, 0, 0);

  return { nodes };
}

function drawTreeConnections(nodes) {
  ctx.strokeStyle = '#4a5568';
  ctx.lineWidth = 1.5;
  ctx.setLineDash([]);

  for (const node of nodes) {
    if (node.childPositions && node.childPositions.length > 0) {
      const parentX = node.x + node.width / 2;
      const parentY = node.y + SCENE_NODE_H;

      for (const childPos of node.childPositions) {
        ctx.beginPath();
        ctx.moveTo(parentX, parentY);
        
        // Draw an elbow connector
        const midY = parentY + (childPos.y - parentY) / 2;
        ctx.lineTo(parentX, midY);
        ctx.lineTo(childPos.x, midY);
        ctx.lineTo(childPos.x, childPos.y);
        
        ctx.stroke();
      }
    }
  }
}

function drawSceneNode(node) {
  const x = node.x;
  const y = node.y;
  const w = node.width;
  const isSelected = selectedSceneNode && selectedSceneNode.path === node.path;
  const isHovered = hoveredSceneNode && hoveredSceneNode.nodePath === node.path;
  const isHighlighted = node.highlighted !== false; // Default to true if not set

  // Node type color
  const nodeColor = getNodeTypeColor(node.type);
  
  // Dim non-highlighted nodes when searching
  ctx.globalAlpha = isHighlighted ? 1 : 0.25;

  // Shadow
  ctx.shadowColor = 'rgba(0,0,0,0.25)';
  ctx.shadowBlur = isHovered ? 12 : 6;
  ctx.shadowOffsetY = 2;

  // Background - highlight matching nodes with a glow
  ctx.beginPath();
  roundRect(ctx, x, y, w, SCENE_NODE_H, 6);
  ctx.fillStyle = isSelected ? '#35353b' : isHovered ? '#303036' : '#242428';
  ctx.fill();

  ctx.shadowBlur = 0;
  ctx.shadowOffsetY = 0;

  // Border - use accent color for highlighted search results
  const borderColor = isSelected ? nodeColor : isHovered ? nodeColor : 
                      (isHighlighted && searchTerm ? '#f9e2af' : '#3a3a40');
  ctx.strokeStyle = borderColor;
  ctx.lineWidth = (isSelected || (isHighlighted && searchTerm)) ? 2 : 1;
  ctx.stroke();

  // Left accent
  ctx.beginPath();
  ctx.roundRect(x + 3, y + 6, 2, SCENE_NODE_H - 12, 1);
  ctx.fillStyle = nodeColor;
  ctx.fill();

  // Node name
  ctx.fillStyle = '#e8e4df';
  ctx.font = `600 11px -apple-system, system-ui, sans-serif`;
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';
  
  const displayName = node.name || 'Node';
  ctx.fillText(displayName, x + 10, y + SCENE_NODE_H / 2 - 4);

  // Node type (smaller, below name)
  ctx.fillStyle = '#706c66';
  ctx.font = `9px -apple-system, system-ui, sans-serif`;
  ctx.fillText(node.type, x + 10, y + SCENE_NODE_H / 2 + 7);

  // Script indicator
  if (node.script) {
    ctx.fillStyle = '#a6e3a1';
    ctx.font = `10px -apple-system, system-ui, sans-serif`;
    ctx.textAlign = 'right';
    ctx.fillText('📜', x + w - 6, y + SCENE_NODE_H / 2);
    ctx.textAlign = 'left';
  }

  // Sibling index indicator (for node order)
  if (node.index !== undefined && node.index >= 0) {
    ctx.fillStyle = '#4a5568';
    ctx.font = `9px -apple-system, system-ui, sans-serif`;
    ctx.textAlign = 'right';
    ctx.fillText(`#${node.index}`, x + w - 6, y + 10);
    ctx.textAlign = 'left';
  }
  
  // Reset alpha
  ctx.globalAlpha = 1;
}

function getSceneColor(scenePath) {
  // Generate consistent color based on path
  const colors = ['#89dceb', '#a6e3a1', '#f9e2af', '#cba6f7', '#f38ba8', '#fab387'];
  let hash = 0;
  for (let i = 0; i < scenePath.length; i++) {
    hash = scenePath.charCodeAt(i) + ((hash << 5) - hash);
  }
  return colors[Math.abs(hash) % colors.length];
}

function getNodeTypeColor(nodeType) {
  // Godot's actual node type colors
  const GODOT_GREEN = '#8eef97';   // Control/UI nodes
  const GODOT_BLUE = '#8da5f3';    // Node2D nodes
  const GODOT_RED = '#fc7f7f';     // Node3D nodes
  const GODOT_GRAY = '#b2b2b2';    // Base Node
  
  // Control/UI nodes (green)
  const controlTypes = [
    'Control', 'Label', 'Button', 'LineEdit', 'TextEdit', 'RichTextLabel',
    'Panel', 'PanelContainer', 'Container', 'BoxContainer', 'VBoxContainer', 
    'HBoxContainer', 'GridContainer', 'MarginContainer', 'ScrollContainer',
    'TabContainer', 'ProgressBar', 'TextureRect', 'ColorRect', 'NinePatchRect',
    'CheckBox', 'CheckButton', 'OptionButton', 'SpinBox', 'Slider', 'HSlider',
    'VSlider', 'Tree', 'ItemList', 'MenuButton', 'LinkButton', 'CanvasLayer'
  ];
  
  // Node2D nodes (blue)
  const node2DTypes = [
    'Node2D', 'Sprite2D', 'AnimatedSprite2D', 'CharacterBody2D', 'RigidBody2D',
    'StaticBody2D', 'Area2D', 'CollisionShape2D', 'CollisionPolygon2D',
    'Camera2D', 'Path2D', 'PathFollow2D', 'Line2D', 'Polygon2D', 'TileMap',
    'TileMapLayer', 'Marker2D', 'RemoteTransform2D', 'VisibleOnScreenNotifier2D',
    'GPUParticles2D', 'CPUParticles2D', 'LightOccluder2D', 'PointLight2D',
    'DirectionalLight2D', 'AudioStreamPlayer2D', 'NavigationRegion2D'
  ];
  
  // Node3D nodes (red)
  const node3DTypes = [
    'Node3D', 'Sprite3D', 'AnimatedSprite3D', 'CharacterBody3D', 'RigidBody3D',
    'StaticBody3D', 'Area3D', 'CollisionShape3D', 'CollisionPolygon3D',
    'Camera3D', 'MeshInstance3D', 'MultiMeshInstance3D', 'CSGBox3D',
    'CSGCylinder3D', 'CSGSphere3D', 'CSGMesh3D', 'Path3D', 'PathFollow3D',
    'GPUParticles3D', 'CPUParticles3D', 'OmniLight3D', 'SpotLight3D',
    'DirectionalLight3D', 'AudioStreamPlayer3D', 'NavigationRegion3D'
  ];
  
  // Check exact matches first, then partial
  for (const type of controlTypes) {
    if (nodeType === type || nodeType.includes(type)) return GODOT_GREEN;
  }
  for (const type of node2DTypes) {
    if (nodeType === type || nodeType.includes(type)) return GODOT_BLUE;
  }
  for (const type of node3DTypes) {
    if (nodeType === type || nodeType.includes(type)) return GODOT_RED;
  }
  
  // Fallback: check for 2D/3D suffix
  if (nodeType.endsWith('2D')) return GODOT_BLUE;
  if (nodeType.endsWith('3D')) return GODOT_RED;
  
  return GODOT_GRAY; // Default gray for base Node
}

function drawSceneViewPlaceholder() {
  ctx.fillStyle = '#706c66';
  ctx.font = `16px -apple-system, system-ui, sans-serif`;
  ctx.textAlign = 'center';
  ctx.fillText('No scenes found', 0, 0);
  ctx.fillText('Create a .tscn file in your project', 0, 24);
  ctx.textAlign = 'left';
}

// Export scene hit testing
export function sceneHitTest(wx, wy) {
  if (!sceneData || !sceneData.scenes) return null;

  if (expandedScene && expandedSceneHierarchy) {
    // Hit test expanded scene nodes
    const treeLayout = calculateTreeLayout(expandedSceneHierarchy);
    for (let i = treeLayout.nodes.length - 1; i >= 0; i--) {
      const node = treeLayout.nodes[i];
      if (wx >= node.x && wx <= node.x + node.width &&
          wy >= node.y && wy <= node.y + SCENE_NODE_H) {
        return { type: 'sceneNode', node, scenePath: expandedScene };
      }
    }
    return null;
  } else {
    // Hit test scene cards
    for (const scene of sceneData.scenes) {
      const pos = scenePositions[scene.path];
      if (!pos) continue;
      
      if (wx >= pos.x && wx <= pos.x + SCENE_CARD_W &&
          wy >= pos.y && wy <= pos.y + SCENE_CARD_H) {
        return { type: 'sceneCard', scene, scenePath: scene.path };
      }
    }
    return null;
  }
}

export { SCENE_CARD_W, SCENE_CARD_H, SCENE_NODE_H };

export function roundRect(ctx, x, y, w, h, r) {
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
}

export function hitTest(wx, wy) {
  for (let i = nodes.length - 1; i >= 0; i--) {
    const n = nodes[i];
    // Skip hidden nodes during search
    if (searchTerm && n.visible === false) continue;
    // Standard node box
    if (wx >= n.x - NODE_W / 2 && wx <= n.x + NODE_W / 2 &&
        wy >= n.y - NODE_H / 2 && wy <= n.y + NODE_H / 2) return n;
    // Extended hit zone for signal port area (right edge through dot+label)
    // Covers the bridge gap between node edge and port dots
    if (n.signals && n.signals.length > 0) {
      const rightEdge = n.x + NODE_W / 2;
      const portRight = rightEdge + SIG_PORT_R * 2 + 8 + 80; // dot + label
      if (wx >= rightEdge && wx <= portRight &&
          wy >= n.y - NODE_H / 2 && wy <= n.y + NODE_H / 2) return n;
    }
  }
  return null;
}

export function centerOnNodes(nodeList) {
  if (!nodeList || nodeList.length === 0) return;

  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  nodeList.forEach(n => {
    minX = Math.min(minX, n.x);
    maxX = Math.max(maxX, n.x);
    minY = Math.min(minY, n.y);
    maxY = Math.max(maxY, n.y);
  });

  camera.x = (minX + maxX) / 2;
  camera.y = (minY + maxY) / 2;
  updateZoomIndicator();
}

export function fitToView(nodeList) {
  if (!nodeList || nodeList.length === 0) return;

  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  nodeList.forEach(n => {
    minX = Math.min(minX, n.x);
    maxX = Math.max(maxX, n.x);
    minY = Math.min(minY, n.y);
    maxY = Math.max(maxY, n.y);
  });

  camera.x = (minX + maxX) / 2;
  camera.y = (minY + maxY) / 2;

  const spanX = (maxX - minX) + NODE_W * 2;
  const spanY = (maxY - minY) + NODE_H * 2;
  // Calculate zoom to fit all nodes, but cap at 100% (1.0) to avoid zooming in too much
  camera.zoom = Math.min(1.0, W / spanX, H / spanY) * 0.9;
  // Don't change defaultZoom - keep it at 1 (100%) so reset always goes to 100%
  updateZoomIndicator();
}
