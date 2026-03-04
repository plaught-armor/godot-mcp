/**
 * Event handlers for mouse, keyboard, and search
 */

import {
  nodes, edges, camera, W, H, defaultZoom,
  dragging, setDragging,
  hoveredNode, setHoveredNode,
  searchTerm, setSearchTerm,
  currentView, expandedScene, expandedSceneHierarchy, sceneData,
  setExpandedScene, setExpandedSceneHierarchy,
  setSelectedSceneNode, setHoveredSceneNode,
  selectedSceneNode, scenePositions, setScenePosition,
  folderGroups,
  connectionDrag, setConnectionDrag
} from './state.js';
import {
  getCanvas, screenToWorld, hitTest, draw, resize,
  updateZoomIndicator, centerOnNodes, savePositions,
  sceneHitTest, SCENE_CARD_W, SCENE_CARD_H,
  getMinimapState, onNodeMoved,
  signalPortHitTest, portHitTest
} from './canvas.js';
import { openPanel, closePanel, openSceneNodePanel, closeSceneNodePanel } from './panel.js';
import { sendCommand } from './websocket.js';
import { undoManager, createCommand } from './undo.js';

const DRAG_THRESHOLD = 5; // pixels - minimum movement to count as drag
let dragRAF = null; // requestAnimationFrame handle for drag rendering

export function initEvents() {
  const canvas = getCanvas();
  const searchInput = document.getElementById('search');
  const statsEl = document.getElementById('stats');

  // Mouse events
  canvas.addEventListener('mousedown', (e) => {
    const w = screenToWorld(e.clientX, e.clientY);
    
    if (currentView === 'scenes') {
      handleSceneMouseDown(e, w);
    } else {
      handleScriptsMouseDown(e, w);
    }
  });

  canvas.addEventListener('mousemove', (e) => {
    if (currentView === 'scenes') {
      handleSceneMouseMove(e);
    } else {
      handleScriptsMouseMove(e);
    }
  });

  canvas.addEventListener('mouseup', (e) => {
    if (currentView === 'scenes') {
      handleSceneMouseUp(e);
    } else {
      handleScriptsMouseUp(e);
    }
  });

  // Prevent click from also opening panel (mouseup already handles it)
  canvas.addEventListener('click', (e) => {
    // Only handle clicks on empty space (not nodes) - nodes are handled by mouseup
  });

  canvas.addEventListener('wheel', (e) => {
    e.preventDefault();
    // Ignore scroll over minimap
    if (currentView === 'scripts' && isInMinimap(e.clientX, e.clientY)) return;
    // Smaller zoom increments for finer control
    const zoomFactor = e.deltaY > 0 ? 0.95 : 1.05;
    const newZoom = Math.max(0.1, Math.min(5, camera.zoom * zoomFactor));
    const wx = (e.clientX - W / 2) / camera.zoom + camera.x;
    const wy = (e.clientY - H / 2) / camera.zoom + camera.y;
    camera.zoom = newZoom;
    camera.x = wx - (e.clientX - W / 2) / camera.zoom;
    camera.y = wy - (e.clientY - H / 2) / camera.zoom;
    updateZoomIndicator();
    draw();
  }, { passive: false });

  // Double-click to rename
  canvas.addEventListener('dblclick', (e) => {
    if (currentView === 'scenes' && expandedScene) {
      const w = screenToWorld(e.clientX, e.clientY);
      const hit = sceneHitTest(w.x, w.y);
      
      if (hit && hit.type === 'sceneNode') {
        e.preventDefault();
        startInlineRename(e.clientX, e.clientY, hit.node, hit.scenePath);
      }
    }
  });

  // Right-click context menu
  canvas.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    
    if (currentView === 'scenes' && expandedScene) {
      const w = screenToWorld(e.clientX, e.clientY);
      const hit = sceneHitTest(w.x, w.y);
      
      if (hit && hit.type === 'sceneNode') {
        showSceneContextMenu(e.clientX, e.clientY, hit.node, hit.scenePath);
        return;
      }
    }
    
    // Hide scene context menu if clicking elsewhere
    hideSceneContextMenu();
  });

  // Close context menus when clicking elsewhere
  document.addEventListener('click', (e) => {
    if (!e.target.closest('#scene-context-menu')) {
      hideSceneContextMenu();
    }
  });

  // Search
  searchInput.addEventListener('input', () => {
    const term = searchInput.value.toLowerCase().trim();
    setSearchTerm(term);

    if (currentView === 'scripts') {
      nodes.forEach(n => {
        if (!term) {
          n.highlighted = true;
          n.visible = true;
          return;
        }
        const matches = n.filename.toLowerCase().includes(term) ||
          (n.class_name && n.class_name.toLowerCase().includes(term)) ||
          (n.description && n.description.toLowerCase().includes(term)) ||
          (n.path && n.path.toLowerCase().includes(term));
        n.highlighted = matches;
        n.visible = matches;
      });

      const matchingNodes = nodes.filter(n => n.highlighted);
      const count = matchingNodes.length;
      statsEl.textContent = term
        ? `${count}/${nodes.length}`
        : `${nodes.length} scripts · ${edges.length} connections`;

      // If there are matching results, center the view on them
      if (term && matchingNodes.length > 0) {
        centerOnNodes(matchingNodes);

        // Adjust zoom if needed to fit all matching nodes
        if (matchingNodes.length === 1) {
          camera.zoom = Math.max(defaultZoom, 1);
        }
        updateZoomIndicator();
      }
    }
    // Scene search
    if (currentView === 'scenes') {
      if (expandedScene && expandedSceneHierarchy) {
        // Search within expanded scene - highlight matching nodes
        const matchingPaths = [];
        
        function searchNode(node) {
          const matches = !term || 
            node.name.toLowerCase().includes(term) ||
            (node.type && node.type.toLowerCase().includes(term));
          
          node.highlighted = matches;
          if (matches && term) matchingPaths.push(node.path);
          
          if (node.children) {
            for (const child of node.children) {
              searchNode(child);
            }
          }
        }
        
        searchNode(expandedSceneHierarchy);
        
        const totalNodes = countNodes(expandedSceneHierarchy);
        statsEl.textContent = term
          ? `${matchingPaths.length}/${totalNodes} nodes`
          : `${totalNodes} nodes`;
      } else if (sceneData && sceneData.scenes) {
        // Search in scene overview
        let matchCount = 0;
        for (const scene of sceneData.scenes) {
          const sceneName = scene.name || scene.path.split('/').pop().replace('.tscn', '');
          scene.highlighted = !term || 
            sceneName.toLowerCase().includes(term) ||
            (scene.root_type && scene.root_type.toLowerCase().includes(term));
          if (scene.highlighted) matchCount++;
        }
        
        statsEl.textContent = term
          ? `${matchCount}/${sceneData.scenes.length} scenes`
          : `${sceneData.scenes.length} scenes`;
      }
    }

    draw();
  });
  
  function countNodes(node) {
    let count = 1;
    if (node.children) {
      for (const child of node.children) {
        count += countNodes(child);
      }
    }
    return count;
  }

  // Keyboard shortcuts
  document.addEventListener('keydown', (e) => {
    // Undo/Redo (skip when typing in inputs)
    if ((e.ctrlKey || e.metaKey) && !e.target.matches('input, textarea, [contenteditable]')) {
      if (e.key === 'z' && !e.shiftKey) { e.preventDefault(); undoManager.undo(); return; }
      if (e.key === 'z' && e.shiftKey) { e.preventDefault(); undoManager.redo(); return; }
      if (e.key === 'y') { e.preventDefault(); undoManager.redo(); return; }
    }

    if (e.key === 'Escape') {
      // Cancel connection drag if active
      if (connectionDrag) {
        document.removeEventListener('mousemove', onCanvasConnectionDragMove);
        document.removeEventListener('mouseup', onCanvasConnectionDragEnd);
        document.body.style.cursor = '';
        setConnectionDrag(null);
        draw();
        return;
      }
      // Also close context menus
      hideSceneContextMenu();
      
      if (currentView === 'scenes') {
        if (selectedSceneNode) {
          setSelectedSceneNode(null);
          closeSceneNodePanel();
          draw();
        } else if (expandedScene) {
          goBackToSceneOverview();
        }
      } else {
        closePanel();
      }
    }
    
    // Focus search with /
    if (e.key === '/' && document.activeElement !== searchInput) {
      e.preventDefault();
      searchInput.focus();
    }
    
    // Delete key to delete selected scene node
    if ((e.key === 'Delete' || e.key === 'Backspace') && currentView === 'scenes' && selectedSceneNode && !e.target.matches('input, textarea')) {
      e.preventDefault();
      sceneNodeAction('delete');
    }
    
    // Enter to open properties panel for selected node
    if (e.key === 'Enter' && currentView === 'scenes' && expandedScene && !e.target.matches('input, textarea')) {
      // If no node selected, select root
      // If node selected, this could toggle the panel (already handled by re-click)
    }
  });

  // Window resize
  window.addEventListener('resize', () => {
    resize();
    draw();
  });
}

// ---- Minimap helpers ----
function isInMinimap(sx, sy) {
  const mm = getMinimapState();
  if (!mm || !mm.rect) return false;
  return sx >= mm.rect.x && sx <= mm.rect.x + mm.rect.w &&
         sy >= mm.rect.y && sy <= mm.rect.y + mm.rect.h;
}

function minimapToWorld(sx, sy) {
  const mm = getMinimapState();
  if (!mm || !mm.worldBounds || !mm.contentOffset) return null;
  const relX = sx - mm.contentOffset.x;
  const relY = sy - mm.contentOffset.y;
  return {
    x: mm.worldBounds.minX + relX / mm.scale,
    y: mm.worldBounds.minY + relY / mm.scale
  };
}

// ---- Folder hit test ----
function folderHitTest(wx, wy) {
  for (const [folder, group] of Object.entries(folderGroups)) {
    const b = group.bounds;
    if (wx >= b.x && wx <= b.x + b.w && wy >= b.y && wy <= b.y + b.h) {
      return { folder, group };
    }
  }
  return null;
}

// ---- Scripts view event handlers ----
function handleScriptsMouseDown(e, w) {
  const canvas = getCanvas();

  // Check minimap first
  if (isInMinimap(e.clientX, e.clientY)) {
    const worldPos = minimapToWorld(e.clientX, e.clientY);
    if (worldPos) {
      camera.x = worldPos.x;
      camera.y = worldPos.y;
      setDragging({ type: 'minimap' });
      updateZoomIndicator();
      draw();
    }
    return;
  }

  // Check signal port dots on hovered node first
  if (hoveredNode && e.button === 0) {
    const sigPort = signalPortHitTest(w.x, w.y, hoveredNode);
    if (sigPort) {
      // Start connection drag from canvas signal port
      setConnectionDrag({
        signalName: sigPort.signalName,
        signalParams: sigPort.signalParams,
        sourceNode: hoveredNode,
        cursorX: e.clientX,
        cursorY: e.clientY,
        targetNode: null,
        hoveredPort: -1
      });
      document.body.style.cursor = 'crosshair';
      document.addEventListener('mousemove', onCanvasConnectionDragMove);
      document.addEventListener('mouseup', onCanvasConnectionDragEnd);
      draw();
      return;
    }
  }

  const hit = hitTest(w.x, w.y);

  if (hit && e.button === 0) {
    setDragging({
      type: 'node',
      node: hit,
      offX: hit.x - w.x,
      offY: hit.y - w.y,
      startScreenX: e.clientX,
      startScreenY: e.clientY,
      moved: false
    });
    canvas.classList.add('dragging');
  } else {
    // Check if clicking on a folder background
    const folderHit = folderHitTest(w.x, w.y);
    if (folderHit && e.button === 0) {
      // Store offsets for all nodes in the folder
      const offsets = folderHit.group.nodes.map(n => ({ node: n, offX: n.x - w.x, offY: n.y - w.y }));
      setDragging({
        type: 'folder',
        folder: folderHit.folder,
        group: folderHit.group,
        offsets,
        startScreenX: e.clientX,
        startScreenY: e.clientY,
        moved: false
      });
      canvas.classList.add('dragging');
    } else {
      setDragging({ type: 'pan', startX: e.clientX, startY: e.clientY, camX: camera.x, camY: camera.y });
      canvas.classList.add('dragging');
    }
  }
}

function handleScriptsMouseMove(e) {
  const canvas = getCanvas();
  if (dragging) {
    if (dragging.type === 'minimap') {
      const worldPos = minimapToWorld(e.clientX, e.clientY);
      if (worldPos) {
        camera.x = worldPos.x;
        camera.y = worldPos.y;
        draw();
      }
      return;
    }
    if (dragging.type === 'folder') {
      const w = screenToWorld(e.clientX, e.clientY);
      for (const { node, offX, offY } of dragging.offsets) {
        node.x = w.x + offX;
        node.y = w.y + offY;
      }
      const dx = Math.abs(e.clientX - dragging.startScreenX);
      const dy = Math.abs(e.clientY - dragging.startScreenY);
      if (dx > DRAG_THRESHOLD || dy > DRAG_THRESHOLD) {
        dragging.moved = true;
      }
      // Batch draw to next frame for smooth folder dragging
      if (!dragRAF) {
        dragRAF = requestAnimationFrame(() => {
          draw();
          dragRAF = null;
        });
      }
      return;
    } else if (dragging.type === 'node') {
      const w = screenToWorld(e.clientX, e.clientY);
      dragging.node.x = w.x + dragging.offX;
      dragging.node.y = w.y + dragging.offY;

      const dx = Math.abs(e.clientX - dragging.startScreenX);
      const dy = Math.abs(e.clientY - dragging.startScreenY);
      if (dx > DRAG_THRESHOLD || dy > DRAG_THRESHOLD) {
        dragging.moved = true;
      }
    } else {
      const dx = (e.clientX - dragging.startX) / camera.zoom;
      const dy = (e.clientY - dragging.startY) / camera.zoom;
      camera.x = dragging.camX - dx;
      camera.y = dragging.camY - dy;
    }
    draw();
  } else {
    // Check minimap hover
    if (isInMinimap(e.clientX, e.clientY)) {
      canvas.style.cursor = 'pointer';
      return;
    }
    const w = screenToWorld(e.clientX, e.clientY);
    const prev = hoveredNode;
    setHoveredNode(hitTest(w.x, w.y));
    if (hoveredNode !== prev) {
      if (hoveredNode) {
        // Check if over a signal port dot
        const sigPort = signalPortHitTest(w.x, w.y, hoveredNode);
        canvas.style.cursor = sigPort ? 'crosshair' : 'pointer';
      } else if (folderHitTest(w.x, w.y)) {
        canvas.style.cursor = 'move';
      } else {
        canvas.style.cursor = 'grab';
      }
      draw();
    } else if (hoveredNode) {
      // Same node but might be moving between port and non-port area
      const sigPort = signalPortHitTest(w.x, w.y, hoveredNode);
      canvas.style.cursor = sigPort ? 'crosshair' : 'pointer';
    }
  }
}

function handleScriptsMouseUp(e) {
  const canvas = getCanvas();
  if (dragging && dragging.type === 'minimap') {
    setDragging(null);
    savePositions();
    return;
  }
  if (dragging && dragging.type === 'folder') {
    if (dragging.moved) {
      onNodeMoved();
    }
  } else if (dragging && dragging.type === 'node') {
    if (dragging.moved) {
      // Node was moved - save positions and recompute folder groups
      onNodeMoved();
    } else {
      // Node was clicked - open panel
      openPanel(dragging.node);
    }
  }
  canvas.classList.remove('dragging');
  setDragging(null);
}

// ---- Canvas-initiated connection drag (from signal port dots) ----
function onCanvasConnectionDragMove(e) {
  if (!connectionDrag) return;
  connectionDrag.cursorX = e.clientX;
  connectionDrag.cursorY = e.clientY;

  const w = screenToWorld(e.clientX, e.clientY);
  const hit = hitTest(w.x, w.y);
  if (hit && hit.functions && hit.functions.length > 0) {
    connectionDrag.targetNode = hit;
    connectionDrag.hoveredPort = portHitTest(w.x, w.y, hit);
  } else {
    connectionDrag.targetNode = null;
    connectionDrag.hoveredPort = -1;
  }

  draw();
}

function onCanvasConnectionDragEnd(e) {
  if (!connectionDrag) return;

  document.removeEventListener('mousemove', onCanvasConnectionDragMove);
  document.removeEventListener('mouseup', onCanvasConnectionDragEnd);
  document.body.style.cursor = '';

  // Check if dropped on a canvas function port
  if (connectionDrag.targetNode && connectionDrag.hoveredPort >= 0) {
    const drag = connectionDrag;
    const targetFunc = drag.targetNode.functions[drag.hoveredPort];
    setConnectionDrag(null);
    draw();
    import('./modals.js').then(m => {
      m.showConnectDialog(drag.sourceNode, drag.signalName, drag.targetNode, targetFunc.name);
    });
    return;
  }

  // Cancelled
  setConnectionDrag(null);
  draw();
}

// ---- Scene view event handlers ----
function handleSceneMouseDown(e, w) {
  const canvas = getCanvas();
  const hit = sceneHitTest(w.x, w.y);

  if (hit && e.button === 0) {
    if (hit.type === 'sceneCard') {
      // Scene card - prepare for possible drag or click
      const pos = scenePositions[hit.scenePath];
      setDragging({
        type: 'sceneCard',
        scene: hit.scene,
        scenePath: hit.scenePath,
        offX: pos.x - w.x,
        offY: pos.y - w.y,
        startScreenX: e.clientX,
        startScreenY: e.clientY,
        moved: false
      });
      canvas.classList.add('dragging');
    } else if (hit.type === 'sceneNode') {
      // Scene node in expanded view - click to select
      setDragging({
        type: 'sceneNode',
        node: hit.node,
        scenePath: hit.scenePath,
        startScreenX: e.clientX,
        startScreenY: e.clientY,
        moved: false
      });
    }
  } else {
    setDragging({ type: 'pan', startX: e.clientX, startY: e.clientY, camX: camera.x, camY: camera.y });
    canvas.classList.add('dragging');
  }
}

function handleSceneMouseMove(e) {
  const canvas = getCanvas();
  if (dragging) {
    if (dragging.type === 'sceneCard') {
      const w = screenToWorld(e.clientX, e.clientY);
      const newX = w.x + dragging.offX;
      const newY = w.y + dragging.offY;
      setScenePosition(dragging.scenePath, newX, newY);

      // Check if moved past threshold
      const dx = Math.abs(e.clientX - dragging.startScreenX);
      const dy = Math.abs(e.clientY - dragging.startScreenY);
      if (dx > DRAG_THRESHOLD || dy > DRAG_THRESHOLD) {
        dragging.moved = true;
      }
      draw();
    } else if (dragging.type === 'pan') {
      const dx = (e.clientX - dragging.startX) / camera.zoom;
      const dy = (e.clientY - dragging.startY) / camera.zoom;
      camera.x = dragging.camX - dx;
      camera.y = dragging.camY - dy;
      draw();
    }
  } else {
    const w = screenToWorld(e.clientX, e.clientY);
    const hit = sceneHitTest(w.x, w.y);
    
    if (hit) {
      if (hit.type === 'sceneCard') {
        setHoveredSceneNode({ scenePath: hit.scenePath, nodePath: null });
      } else if (hit.type === 'sceneNode') {
        setHoveredSceneNode({ scenePath: hit.scenePath, nodePath: hit.node.path });
      }
      canvas.style.cursor = 'pointer';
    } else {
      setHoveredSceneNode(null);
      canvas.style.cursor = 'grab';
    }
    draw();
  }
}

function handleSceneMouseUp(e) {
  const canvas = getCanvas();
  
  if (dragging) {
    if (dragging.type === 'sceneCard' && !dragging.moved) {
      // Scene card was clicked - expand the scene
      expandScene(dragging.scenePath);
    } else if (dragging.type === 'sceneNode' && !dragging.moved) {
      // Scene node was clicked - select it and open properties panel
      selectSceneNode(dragging.node, dragging.scenePath);
    }
  }
  
  canvas.classList.remove('dragging');
  setDragging(null);
}

// ---- Scene expansion and navigation ----
async function expandScene(scenePath) {
  try {
    // Fetch the scene hierarchy
    const result = await sendCommand('get_scene_hierarchy', { scene_path: scenePath });
    
    if (result.ok) {
      setExpandedScene(scenePath);
      setExpandedSceneHierarchy(result.hierarchy);
      
      // Reset camera position but keep user's zoom level
      camera.x = 0;
      camera.y = 100;
      // Don't change zoom - keep user's preference
      
      // Update UI
      updateSceneBackButton(true, scenePath);
      draw();
    } else {
      console.error('Failed to get scene hierarchy:', result.error);
      alert('Failed to load scene: ' + (result.error || 'Unknown error'));
    }
  } catch (err) {
    console.error('Failed to expand scene:', err);
    alert('Failed to load scene: ' + err.message);
  }
}

async function selectSceneNode(node, scenePath) {
  // If clicking the same node that's already selected, close the panel
  if (selectedSceneNode && selectedSceneNode.path === node.path) {
    setSelectedSceneNode(null);
    closeSceneNodePanel();
    draw();
    return;
  }
  
  setSelectedSceneNode(node);
  
  // Open the properties panel for this node
  await openSceneNodePanel(scenePath, node);
  draw();
}

export function goBackToSceneOverview() {
  setExpandedScene(null);
  setExpandedSceneHierarchy(null);
  setSelectedSceneNode(null);
  setHoveredSceneNode(null);
  closeSceneNodePanel();
  updateSceneBackButton(false);
  draw();
}

function updateSceneBackButton(show, scenePath = '') {
  const backBtn = document.getElementById('scene-back-btn');
  const legend = document.getElementById('legend');
  
  if (backBtn) {
    backBtn.style.display = show ? 'flex' : 'none';
    if (show) {
      const sceneName = scenePath.split('/').pop().replace('.tscn', '');
      backBtn.querySelector('.scene-name').textContent = sceneName;
    }
  }
  
  // Hide legend when in expanded scene view (it's not relevant there)
  if (legend) {
    legend.classList.toggle('hidden', show);
  }
}

// Expose for global access
window.goBackToSceneOverview = goBackToSceneOverview;
window.expandSceneFromPanel = expandScene;

export function updateStats() {
  const scriptsEl = document.getElementById('scripts-indicator');
  const connectionsEl = document.getElementById('connections-indicator');
  const gitEl = document.getElementById('git-indicator');
  const depEl = document.getElementById('dep-indicator');

  if (currentView === 'scripts') {
    scriptsEl.textContent = `${nodes.length} scripts`;
    connectionsEl.textContent = `${edges.length} connections`;
    scriptsEl.style.display = '';
    connectionsEl.style.display = '';

    // Git status indicator
    const gitModified = nodes.filter(n => n.gitStatus).length;
    if (gitModified > 0 && gitEl) {
      const added = nodes.filter(n => n.gitStatus === 'added').length;
      const modified = nodes.filter(n => n.gitStatus === 'modified').length;
      const parts = [];
      if (modified > 0) parts.push(`${modified}M`);
      if (added > 0) parts.push(`${added}A`);
      const other = gitModified - modified - added;
      if (other > 0) parts.push(`${other}?`);
      gitEl.textContent = `● ${parts.join(' ')}`;
      gitEl.title = `Git: ${gitModified} changed file${gitModified > 1 ? 's' : ''}`;
      gitEl.style.display = '';
    } else if (gitEl) {
      gitEl.style.display = 'none';
    }

    // Dependency indicator
    const cycleCount = nodes.filter(n => n._inCycle).length;
    const orphanCount = nodes.filter(n => n._orphaned).length;
    if ((cycleCount > 0 || orphanCount > 0) && depEl) {
      const parts = [];
      if (cycleCount > 0) parts.push(`${cycleCount} circular`);
      if (orphanCount > 0) parts.push(`${orphanCount} orphaned`);
      depEl.textContent = `▲ ${parts.join(', ')}`;
      depEl.title = 'Dependency issues detected';
      depEl.style.display = '';
    } else if (depEl) {
      depEl.style.display = 'none';
    }
  } else {
    if (gitEl) gitEl.style.display = 'none';
    if (depEl) depEl.style.display = 'none';
    if (sceneData && sceneData.scenes) {
      scriptsEl.textContent = `${sceneData.scenes.length} scenes`;
      scriptsEl.style.display = '';
    }
    connectionsEl.style.display = 'none';
  }
}

// ---- Scene Node Context Menu ----
let contextMenuNode = null;
let contextMenuScenePath = null;

function showSceneContextMenu(x, y, node, scenePath) {
  const menu = document.getElementById('scene-context-menu');
  contextMenuNode = node;
  contextMenuScenePath = scenePath;
  
  menu.style.left = x + 'px';
  menu.style.top = y + 'px';
  menu.classList.add('visible');
}

function hideSceneContextMenu() {
  const menu = document.getElementById('scene-context-menu');
  menu.classList.remove('visible');
  contextMenuNode = null;
  contextMenuScenePath = null;
}

async function sceneNodeAction(action) {
  // Save node info BEFORE hiding menu (which clears these variables)
  const node = contextMenuNode;
  const scenePath = contextMenuScenePath;

  hideSceneContextMenu();

  if (!node || !scenePath) return;

  try {
    switch (action) {
      case 'add_child': {
        const nodeType = prompt('Enter node type (e.g., Node2D, Sprite2D, Label):', 'Node2D');
        if (!nodeType) return;
        const nodeName = prompt('Enter node name:', 'NewNode');
        if (!nodeName) return;

        const parentPath = node.path;
        const childPath = parentPath === '.' ? nodeName : parentPath + '/' + nodeName;

        const command = createCommand(
          `Add node '${nodeName}'`,
          async () => {
            const result = await sendCommand('add_node', {
              scene_path: scenePath, parent_path: parentPath,
              node_type: nodeType, node_name: nodeName
            });
            if (!result.ok) throw new Error(result.error || 'Unknown error');
            await refreshExpandedScene(scenePath);
          },
          async () => {
            const result = await sendCommand('remove_node', {
              scene_path: scenePath, node_path: childPath
            });
            if (!result.ok) throw new Error(result.error || 'Unknown error');
            await refreshExpandedScene(scenePath);
          }
        );
        await undoManager.execute(command);
        break;
      }

      case 'rename': {
        const newName = prompt('Enter new name:', node.name);
        if (!newName || newName === node.name) return;

        const oldName = node.name;
        const oldPath = node.path;
        // Compute what path will be after rename
        const parts = oldPath.split('/');
        parts[parts.length - 1] = newName;
        const newPath = parts.join('/');

        const command = createCommand(
          `Rename node '${oldName}' to '${newName}'`,
          async () => {
            const result = await sendCommand('rename_node', {
              scene_path: scenePath, node_path: oldPath, new_name: newName
            });
            if (!result.ok) throw new Error(result.error || 'Unknown error');
            await refreshExpandedScene(scenePath);
          },
          async () => {
            const result = await sendCommand('rename_node', {
              scene_path: scenePath, node_path: newPath, new_name: oldName
            });
            if (!result.ok) throw new Error(result.error || 'Unknown error');
            await refreshExpandedScene(scenePath);
          }
        );
        await undoManager.execute(command);
        break;
      }

      case 'duplicate': {
        // After duplicate, find the new node to know its path for undo
        const command = createCommand(
          `Duplicate node '${node.name}'`,
          async () => {
            const result = await sendCommand('duplicate_node', {
              scene_path: scenePath, node_path: node.path
            });
            if (!result.ok) throw new Error(result.error || 'Unknown error');
            await refreshExpandedScene(scenePath);
          },
          async () => {
            // The duplicated node is typically named NodeName2, NodeName3, etc.
            // Re-fetch hierarchy and find the newest sibling
            await refreshExpandedScene(scenePath);
          }
        );
        await undoManager.execute(command);
        break;
      }

      case 'move_up': {
        if (node.index === undefined || node.index <= 0) {
          alert('Cannot move node up - already at top');
          return;
        }
        const originalIndex = node.index;
        const newIndex = node.index - 1;

        const command = createCommand(
          `Move node '${node.name}' up`,
          async () => {
            const result = await sendCommand('reorder_node', {
              scene_path: scenePath, node_path: node.path, new_index: newIndex
            });
            if (!result.ok) throw new Error(result.error || 'Unknown error');
            await refreshExpandedScene(scenePath);
          },
          async () => {
            const result = await sendCommand('reorder_node', {
              scene_path: scenePath, node_path: node.path, new_index: originalIndex
            });
            if (!result.ok) throw new Error(result.error || 'Unknown error');
            await refreshExpandedScene(scenePath);
          }
        );
        await undoManager.execute(command);
        break;
      }

      case 'move_down': {
        const originalIndex = node.index || 0;
        const newIndex = originalIndex + 1;

        const command = createCommand(
          `Move node '${node.name}' down`,
          async () => {
            const result = await sendCommand('reorder_node', {
              scene_path: scenePath, node_path: node.path, new_index: newIndex
            });
            if (!result.ok) throw new Error(result.error || 'Unknown error');
            await refreshExpandedScene(scenePath);
          },
          async () => {
            const result = await sendCommand('reorder_node', {
              scene_path: scenePath, node_path: node.path, new_index: originalIndex
            });
            if (!result.ok) throw new Error(result.error || 'Unknown error');
            await refreshExpandedScene(scenePath);
          }
        );
        await undoManager.execute(command);
        break;
      }

      case 'delete': {
        if (node.path === '.') {
          alert('Cannot delete root node');
          return;
        }
        if (!confirm(`Delete node "${node.name}" and all its children?`)) return;

        const savedNode = { name: node.name, type: node.type, path: node.path, index: node.index };
        // Compute parent path
        const pathParts = node.path.split('/');
        pathParts.pop();
        const parentPath = pathParts.length > 0 ? pathParts.join('/') : '.';

        const command = createCommand(
          `Delete node '${node.name}'`,
          async () => {
            const result = await sendCommand('remove_node', {
              scene_path: scenePath, node_path: savedNode.path
            });
            if (!result.ok) throw new Error(result.error || 'Unknown error');
            closeSceneNodePanel();
            setSelectedSceneNode(null);
            await refreshExpandedScene(scenePath);
          },
          async () => {
            // Re-create the node (top-level only, children not restored)
            const result = await sendCommand('add_node', {
              scene_path: scenePath, parent_path: parentPath,
              node_type: savedNode.type || 'Node', node_name: savedNode.name
            });
            if (!result.ok) throw new Error(result.error || 'Unknown error');
            await refreshExpandedScene(scenePath);
          }
        );
        await undoManager.execute(command);
        break;
      }
    }
  } catch (err) {
    console.error('Scene action failed:', err);
    alert('Action failed: ' + err.message);
  }
}

async function refreshExpandedScene(scenePath) {
  // Re-fetch the scene hierarchy
  const result = await sendCommand('get_scene_hierarchy', { scene_path: scenePath });
  if (result.ok && result.hierarchy) {
    setExpandedSceneHierarchy(result.hierarchy);
    draw();
  }
}

// ---- Inline Rename ----
function startInlineRename(screenX, screenY, node, scenePath) {
  // Create an input overlay at the node position
  const existingInput = document.getElementById('inline-rename-input');
  if (existingInput) existingInput.remove();
  
  const input = document.createElement('input');
  input.id = 'inline-rename-input';
  input.type = 'text';
  input.value = node.name;
  input.style.cssText = `
    position: fixed;
    left: ${screenX - 50}px;
    top: ${screenY - 12}px;
    width: 120px;
    padding: 4px 8px;
    font-size: 12px;
    font-family: -apple-system, system-ui, sans-serif;
    font-weight: 600;
    background: #242428;
    border: 2px solid #7aa2f7;
    border-radius: 4px;
    color: #e8e4df;
    z-index: 1000;
    outline: none;
  `;
  
  document.body.appendChild(input);
  input.focus();
  input.select();
  
  async function finishRename() {
    const newName = input.value.trim();
    input.remove();

    if (newName && newName !== node.name) {
      const oldName = node.name;
      const oldPath = node.path;
      const parts = oldPath.split('/');
      parts[parts.length - 1] = newName;
      const newPath = parts.join('/');

      const command = createCommand(
        `Rename node '${oldName}' to '${newName}'`,
        async () => {
          const result = await sendCommand('rename_node', {
            scene_path: scenePath, node_path: oldPath, new_name: newName
          });
          if (!result.ok) throw new Error(result.error || 'Unknown error');
          await refreshExpandedScene(scenePath);
        },
        async () => {
          const result = await sendCommand('rename_node', {
            scene_path: scenePath, node_path: newPath, new_name: oldName
          });
          if (!result.ok) throw new Error(result.error || 'Unknown error');
          await refreshExpandedScene(scenePath);
        }
      );

      try {
        await undoManager.execute(command);
      } catch (err) {
        alert('Failed to rename: ' + err.message);
      }
    }
  }
  
  input.addEventListener('blur', finishRename);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      input.blur();
    } else if (e.key === 'Escape') {
      e.preventDefault();
      input.value = node.name; // Reset to original
      input.blur();
    }
  });
}

// Expose for global access
window.sceneNodeAction = sceneNodeAction;
