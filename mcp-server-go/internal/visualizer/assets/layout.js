/**
 * Force-directed layout algorithm for node positioning
 */

import { nodes, edges, NODE_W, NODE_H, getRootFolder } from './state.js';

// Minimum spacing between nodes
const MIN_SPACING_X = NODE_W + 80;
const MIN_SPACING_Y = NODE_H + 60;

export function initLayout() {
  if (nodes.length === 0) return;

  // Build adjacency map for connected nodes
  const adjacency = new Map();
  nodes.forEach(n => adjacency.set(n.path, []));

  edges.forEach(e => {
    if (adjacency.has(e.from) && adjacency.has(e.to)) {
      adjacency.get(e.from).push(e.to);
      adjacency.get(e.to).push(e.from);
    }
  });

  // Find root nodes (most connections or extends nothing)
  const connectionCount = new Map();
  nodes.forEach(n => {
    const count = (adjacency.get(n.path) || []).length;
    connectionCount.set(n.path, count);
  });

  // Sort nodes by connection count (most connected first)
  const sortedNodes = [...nodes].sort((a, b) =>
    connectionCount.get(b.path) - connectionCount.get(a.path)
  );

  // Initial placement: spread nodes in a grid with good spacing
  const cols = Math.ceil(Math.sqrt(nodes.length));
  const startX = -(cols * MIN_SPACING_X) / 2;
  const startY = -(Math.ceil(nodes.length / cols) * MIN_SPACING_Y) / 2;

  sortedNodes.forEach((n, i) => {
    const col = i % cols;
    const row = Math.floor(i / cols);
    n.x = startX + col * MIN_SPACING_X;
    n.y = startY + row * MIN_SPACING_Y;
  });

  // Run force-directed simulation with collision detection
  const iterations = 150;
  for (let iter = 0; iter < iterations; iter++) {
    const alpha = Math.pow(1 - iter / iterations, 2); // Quadratic cooling
    applyForces(alpha, adjacency);
    resolveCollisions();
  }

  // Final collision resolution passes — keep going until no overlaps remain
  for (let i = 0; i < 50; i++) {
    if (!resolveCollisions()) break; // Stop early if nothing overlaps
  }

  // Arrange each folder's nodes into a grid around its centroid
  snapFoldersToGrid();

  // Arrange subfolder groups into a grid within each root folder
  snapRootFoldersToGrid();

  // Final collision resolution between folder groups
  for (let i = 0; i < 50; i++) {
    if (!resolveCollisions()) break;
  }

  // Center the layout
  centerLayout();
}

const MAX_ROWS = 4;

function snapFoldersToGrid() {
  const folderMap = {};
  for (const n of nodes) {
    const key = n.folder || '__none__';
    if (!folderMap[key]) folderMap[key] = [];
    folderMap[key].push(n);
  }

  for (const [folder, group] of Object.entries(folderMap)) {
    if (group.length < 2) continue;

    // Find centroid of where the force layout placed them
    let cx = 0, cy = 0;
    for (const n of group) { cx += n.x; cy += n.y; }
    cx /= group.length;
    cy /= group.length;

    // Sort by name for consistent ordering
    group.sort((a, b) => a.filename.localeCompare(b.filename));

    // Column-major: fill columns vertically (max MAX_ROWS per column)
    const rows = Math.min(group.length, MAX_ROWS);
    const cols = Math.ceil(group.length / rows);
    const gridW = cols * MIN_SPACING_X;
    const gridH = rows * MIN_SPACING_Y;

    for (let i = 0; i < group.length; i++) {
      const col = Math.floor(i / MAX_ROWS);
      const row = i % MAX_ROWS;
      group[i].x = cx - gridW / 2 + col * MIN_SPACING_X + MIN_SPACING_X / 2 - NODE_W / 2;
      group[i].y = cy - gridH / 2 + row * MIN_SPACING_Y + MIN_SPACING_Y / 2 - NODE_H / 2;
    }
  }
}

const ROOT_FOLDER_GAP = 60; // Gap between subfolder groups within a root folder

function snapRootFoldersToGrid() {
  // Group subfolders by root folder
  const rootMap = {}; // rootFolder → [{ folder, nodes, bounds }]
  const folderMap = {};
  for (const n of nodes) {
    const key = n.folder || '__none__';
    if (!folderMap[key]) folderMap[key] = [];
    folderMap[key].push(n);
  }

  for (const [folder, group] of Object.entries(folderMap)) {
    if (folder === '__none__') continue;
    const root = getRootFolder(folder);
    if (!root) continue;
    if (!rootMap[root]) rootMap[root] = [];

    // Compute bounding box of this subfolder's nodes (already grid-snapped)
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const n of group) {
      minX = Math.min(minX, n.x - NODE_W / 2);
      maxX = Math.max(maxX, n.x + NODE_W / 2);
      minY = Math.min(minY, n.y - NODE_H / 2);
      maxY = Math.max(maxY, n.y + NODE_H / 2);
    }
    let cx = 0, cy = 0;
    for (const n of group) { cx += n.x; cy += n.y; }
    cx /= group.length; cy /= group.length;

    rootMap[root].push({
      folder,
      nodes: group,
      w: maxX - minX,
      h: maxY - minY,
      cx, cy
    });
  }

  // For each root folder with 2+ subfolders, arrange them in a grid
  for (const [root, subfolders] of Object.entries(rootMap)) {
    if (subfolders.length < 2) continue;

    // Sort subfolders by name for consistent ordering
    subfolders.sort((a, b) => a.folder.localeCompare(b.folder));

    // Compute root centroid (average of subfolder centroids)
    let rootCx = 0, rootCy = 0;
    for (const sf of subfolders) { rootCx += sf.cx; rootCy += sf.cy; }
    rootCx /= subfolders.length;
    rootCy /= subfolders.length;

    // Grid layout for subfolders (max 2 rows to keep things wide)
    const maxRows = Math.min(subfolders.length, 2);
    const gridCols = Math.ceil(subfolders.length / maxRows);

    // Compute column widths and row heights based on actual subfolder sizes
    const colWidths = new Array(gridCols).fill(0);
    const rowHeights = new Array(maxRows).fill(0);

    for (let i = 0; i < subfolders.length; i++) {
      const col = Math.floor(i / maxRows);
      const row = i % maxRows;
      colWidths[col] = Math.max(colWidths[col], subfolders[i].w);
      rowHeights[row] = Math.max(rowHeights[row], subfolders[i].h);
    }

    // Total grid dimensions with gaps
    const totalW = colWidths.reduce((a, b) => a + b, 0) + (gridCols - 1) * ROOT_FOLDER_GAP;
    const totalH = rowHeights.reduce((a, b) => a + b, 0) + (maxRows - 1) * ROOT_FOLDER_GAP;

    // Place each subfolder group
    for (let i = 0; i < subfolders.length; i++) {
      const col = Math.floor(i / maxRows);
      const row = i % maxRows;
      const sf = subfolders[i];

      // Target center for this cell
      let cellX = rootCx - totalW / 2;
      for (let c = 0; c < col; c++) cellX += colWidths[c] + ROOT_FOLDER_GAP;
      cellX += colWidths[col] / 2;

      let cellY = rootCy - totalH / 2;
      for (let r = 0; r < row; r++) cellY += rowHeights[r] + ROOT_FOLDER_GAP;
      cellY += rowHeights[row] / 2;

      // Translate all nodes in this subfolder from current centroid to target
      const dx = cellX - sf.cx;
      const dy = cellY - sf.cy;
      for (const n of sf.nodes) {
        n.x += dx;
        n.y += dy;
      }
    }
  }
}

function applyForces(alpha, adjacency) {
  const repulsion = 80000;  // Strong repulsion
  const attraction = 0.08;  // Moderate attraction
  const idealEdgeLength = MIN_SPACING_X * 1.2;

  // Repulsion between all nodes (weaker within same folder)
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      const a = nodes[i];
      const b = nodes[j];
      let dx = b.x - a.x;
      let dy = b.y - a.y;

      if (dx === 0 && dy === 0) {
        dx = (Math.random() - 0.5) * 10;
        dy = (Math.random() - 0.5) * 10;
      }

      const dist = Math.sqrt(dx * dx + dy * dy) || 1;
      const sameFolder = a.folder && a.folder === b.folder;

      // Same-folder nodes only repel enough to avoid overlap, not to spread apart
      let force = repulsion / (dist * dist);
      if (sameFolder) {
        force *= 0.3;
      } else if (dist < MIN_SPACING_X) {
        force *= 3;
      }

      const fx = (dx / dist) * force * alpha;
      const fy = (dy / dist) * force * alpha;
      a.x -= fx;
      a.y -= fy;
      b.x += fx;
      b.y += fy;
    }
  }

  // Attraction along edges - pull connected nodes together
  // Cross-folder edges are much weaker so they don't stretch folder clusters
  edges.forEach(e => {
    const from = nodes.find(n => n.path === e.from);
    const to = nodes.find(n => n.path === e.to);
    if (!from || !to) return;

    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const dist = Math.sqrt(dx * dx + dy * dy) || 1;

    if (dist > idealEdgeLength) {
      const crossFolder = from.folder !== to.folder;
      const strength = crossFolder ? attraction * 0.15 : attraction;
      const force = (dist - idealEdgeLength) * strength * alpha;
      const fx = (dx / dist) * force;
      const fy = (dy / dist) * force;
      from.x += fx;
      from.y += fy;
      to.x -= fx;
      to.y -= fy;
    }
  });

  // Build folder map (shared by cohesion + repulsion)
  const folderMap = {};
  for (const n of nodes) {
    if (!n.folder) continue;
    if (!folderMap[n.folder]) folderMap[n.folder] = [];
    folderMap[n.folder].push(n);
  }

  // Folder cohesion — attract same-folder nodes toward their centroid
  const folderCohesion = 0.1;
  const folderBounds = {};
  for (const [folder, group] of Object.entries(folderMap)) {
    if (group.length < 2) continue;
    let cx = 0, cy = 0;
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    for (const n of group) {
      cx += n.x; cy += n.y;
      minX = Math.min(minX, n.x); maxX = Math.max(maxX, n.x + NODE_W);
      minY = Math.min(minY, n.y); maxY = Math.max(maxY, n.y + NODE_H);
    }
    cx /= group.length;
    cy /= group.length;
    folderBounds[folder] = { cx, cy, minX, minY, maxX, maxY };
    for (const n of group) {
      const dx = cx - n.x;
      const dy = cy - n.y;
      const dist = Math.sqrt(dx * dx + dy * dy) || 1;
      const force = dist * folderCohesion * alpha;
      n.x += (dx / dist) * force;
      n.y += (dy / dist) * force;
    }
  }

  // Folder repulsion — push based on bounding box gap, not centroid distance
  const folderGap = 80; // Desired minimum gap between folder edges
  const folders = Object.keys(folderBounds);
  for (let i = 0; i < folders.length; i++) {
    for (let j = i + 1; j < folders.length; j++) {
      const a = folderBounds[folders[i]];
      const b = folderBounds[folders[j]];

      // Direction between centroids
      let dx = b.cx - a.cx;
      let dy = b.cy - a.cy;
      if (dx === 0 && dy === 0) {
        dx = (Math.random() - 0.5) * 20;
        dy = (Math.random() - 0.5) * 20;
      }

      // Edge-to-edge gap (negative = overlapping)
      const gapX = Math.max(b.minX - a.maxX, a.minX - b.maxX);
      const gapY = Math.max(b.minY - a.maxY, a.minY - b.maxY);
      const gap = Math.max(gapX, gapY); // Closest edge gap

      // Push if gap is less than desired
      if (gap < folderGap) {
        const dist = Math.sqrt(dx * dx + dy * dy) || 1;
        const push = (folderGap - gap) * 0.3 * alpha;
        const fx = (dx / dist) * push;
        const fy = (dy / dist) * push;
        for (const n of folderMap[folders[i]]) { n.x -= fx; n.y -= fy; }
        for (const n of folderMap[folders[j]]) { n.x += fx; n.y += fy; }
      }
    }
  }

  // Root-folder cohesion — pull nodes sharing the same root directory together
  const rootFolderMap = {};
  for (const n of nodes) {
    const root = getRootFolder(n.folder);
    if (!root) continue;
    if (!rootFolderMap[root]) rootFolderMap[root] = [];
    rootFolderMap[root].push(n);
  }

  const rootCohesion = 0.02; // Weaker than subfolder cohesion (0.1)
  for (const group of Object.values(rootFolderMap)) {
    if (group.length < 3) continue; // Only meaningful with 3+ nodes
    let cx = 0, cy = 0;
    for (const n of group) { cx += n.x; cy += n.y; }
    cx /= group.length;
    cy /= group.length;
    for (const n of group) {
      const dx = cx - n.x;
      const dy = cy - n.y;
      const dist = Math.sqrt(dx * dx + dy * dy) || 1;
      const force = dist * rootCohesion * alpha;
      n.x += (dx / dist) * force;
      n.y += (dy / dist) * force;
    }
  }
}

function resolveCollisions() {
  let hadOverlap = false;
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      const a = nodes[i];
      const b = nodes[j];

      const overlapX = MIN_SPACING_X - Math.abs(b.x - a.x);
      const overlapY = MIN_SPACING_Y - Math.abs(b.y - a.y);

      if (overlapX > 0 && overlapY > 0) {
        hadOverlap = true;
        let dx = b.x - a.x;
        let dy = b.y - a.y;

        if (dx === 0) dx = (Math.random() - 0.5) * 2;
        if (dy === 0) dy = (Math.random() - 0.5) * 2;

        // Push by full overlap + margin so they clear in fewer passes
        if (overlapX < overlapY) {
          const push = (overlapX / 2 + 10) * Math.sign(dx);
          a.x -= push;
          b.x += push;
        } else {
          const push = (overlapY / 2 + 10) * Math.sign(dy);
          a.y -= push;
          b.y += push;
        }
      }
    }
  }
  return hadOverlap;
}

function centerLayout() {
  if (nodes.length === 0) return;

  // Find bounding box
  let minX = Infinity, maxX = -Infinity;
  let minY = Infinity, maxY = -Infinity;

  nodes.forEach(n => {
    minX = Math.min(minX, n.x);
    maxX = Math.max(maxX, n.x);
    minY = Math.min(minY, n.y);
    maxY = Math.max(maxY, n.y);
  });

  // Center around origin
  const centerX = (minX + maxX) / 2;
  const centerY = (minY + maxY) / 2;

  nodes.forEach(n => {
    n.x -= centerX;
    n.y -= centerY;
  });
}
