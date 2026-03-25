/**
 * Context menu, new script modal, and view switching
 */

import {
  nodes, edges, currentView, setCurrentView, setSceneData, getFolderColor,
  setExpandedScene, setExpandedSceneHierarchy, setSelectedSceneNode,
  setHoveredSceneNode, expandedScene
} from './state.js';
import { sendCommand } from './websocket.js';
import { draw, getCanvas, clearPositions, fitToView, screenToWorld, hitTest } from './canvas.js';
import { initLayout } from './layout.js';
import { closePanel, closeSceneNodePanel } from './panel.js';
import { updateStats } from './events.js';
import { undoManager, createCommand } from './undo.js';

let contextMenu;
let rightClickedNode = null; // Script node that was right-clicked

export function initModals() {
  contextMenu = document.getElementById('context-menu');
  initContextMenu();
}

// ---- Context Menu ----
function initContextMenu() {
  const canvas = getCanvas();

  canvas.addEventListener('contextmenu', (e) => {
    e.preventDefault();

    // Only show scripts context menu in scripts view
    if (currentView !== 'scripts') return;

    // Detect if a script node is under the cursor
    const w = screenToWorld(e.clientX, e.clientY);
    rightClickedNode = hitTest(w.x, w.y);

    // Show/hide script-specific actions
    const nodeActions = document.getElementById('script-node-actions');
    if (nodeActions) {
      nodeActions.style.display = rightClickedNode ? '' : 'none';
    }

    // Position menu at mouse
    contextMenu.style.left = e.clientX + 'px';
    contextMenu.style.top = e.clientY + 'px';
    contextMenu.classList.add('visible');
  });

  // Hide context menu on click elsewhere
  document.addEventListener('click', (e) => {
    if (!contextMenu.contains(e.target)) {
      contextMenu.classList.remove('visible');
      rightClickedNode = null;
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      contextMenu.classList.remove('visible');
      rightClickedNode = null;
      closeNewScriptModal();
      closeRenameScriptModal();
      closeDeleteScriptModal();
    }
  });
}

// ---- New Script Creation ----
let usingCustomFolder = false;

window.createNewScript = function () {
  contextMenu.classList.remove('visible');

  // Populate folder dropdown from project nodes
  const folderSelect = document.getElementById('new-script-folder');
  const folders = [...new Set(nodes.map(n => n.folder).filter(Boolean))].sort();

  folderSelect.innerHTML = '';
  for (const folder of folders) {
    const opt = document.createElement('option');
    opt.value = folder;
    opt.textContent = folder.replace('res://', '');
    folderSelect.appendChild(opt);
  }

  // Reset to dropdown mode
  usingCustomFolder = false;
  folderSelect.style.display = '';
  document.getElementById('new-script-custom-folder').style.display = 'none';

  document.getElementById('new-script-modal').style.display = 'flex';
  document.getElementById('new-script-filename').focus();
};

window.toggleCustomFolder = function () {
  usingCustomFolder = !usingCustomFolder;
  const folderSelect = document.getElementById('new-script-folder');
  const customInput = document.getElementById('new-script-custom-folder');
  folderSelect.style.display = usingCustomFolder ? 'none' : '';
  customInput.style.display = usingCustomFolder ? '' : 'none';
  if (usingCustomFolder) {
    customInput.value = folderSelect.value || 'res://';
    customInput.focus();
  }
};

function closeNewScriptModal() {
  document.getElementById('new-script-modal').style.display = 'none';
}
window.closeNewScriptModal = closeNewScriptModal;

window.submitNewScript = async function () {
  let folder = usingCustomFolder
    ? document.getElementById('new-script-custom-folder').value.trim()
    : document.getElementById('new-script-folder').value;
  let filename = document.getElementById('new-script-filename').value.trim();

  if (!folder) {
    alert('Please select a folder');
    return;
  }
  if (!filename) {
    alert('Please enter a filename');
    return;
  }

  // Ensure folder starts with res://
  if (!folder.startsWith('res://')) folder = 'res://' + folder;
  // Ensure folder ends with /
  if (!folder.endsWith('/')) folder += '/';
  // Ensure filename ends with .gd
  if (!filename.endsWith('.gd')) filename += '.gd';

  const path = folder + filename;
  const extendsType = document.getElementById('new-script-extends').value;
  const className = document.getElementById('new-script-classname').value.trim();

  const command = createCommand(
    `Create script '${filename}'`,
    async () => {
      const result = await sendCommand('create_script_file', {
        path, extends: extendsType, class_name: className || ''
      });
      if (result.error) throw new Error(result.error || 'Unknown error');
      await refreshProject();
    },
    async () => {
      const result = await sendCommand('delete_script', { path });
      if (result.error) throw new Error(result.error || 'Unknown error');
      await refreshProject();
    }
  );

  try {
    await undoManager.execute(command);
    closeNewScriptModal();
  } catch (err) {
    alert('Failed to create script: ' + err.message);
  }
};

async function refreshProject() {
  contextMenu.classList.remove('visible');
  try {
    const result = await sendCommand('map_project', {});
    if (!result.error && result.project_map) {
      // Update nodes and edges
      const newNodes = result.project_map.nodes.map((n, i) => ({
        ...n,
        x: nodes[i]?.x || 0,
        y: nodes[i]?.y || 0,
        color: getFolderColor(n.folder),
        highlighted: true,
        visible: true
      }));
      nodes.length = 0;
      nodes.push(...newNodes);
      edges.length = 0;
      edges.push(...result.project_map.edges);
      initLayout();
      draw();
    }
  } catch (err) {
    console.error('Failed to refresh:', err);
  }
}
window.refreshProject = refreshProject;

// ---- Reset Layout ----
window.resetLayout = function () {
  contextMenu.classList.remove('visible');
  // Clear saved positions
  clearPositions();
  // Re-run force-directed layout
  initLayout();
  // Fit view to show all nodes
  fitToView(nodes);
  // Redraw
  draw();
};

// ---- View Switching (Scripts/Scenes) ----
window.switchView = function (view) {
  const currentViewTab = document.querySelector('#view-tabs button.active')?.textContent.toLowerCase();
  if (view === currentViewTab) return;

  // Close any open panels
  if (view === 'scripts') {
    closeSceneNodePanel();
    // Clear scene state
    setExpandedScene(null);
    setExpandedSceneHierarchy(null);
    setSelectedSceneNode(null);
    setHoveredSceneNode(null);
    // Hide scene back button
    const backBtn = document.getElementById('scene-back-btn');
    if (backBtn) backBtn.style.display = 'none';
    // Show legend for scripts view
    const legend = document.getElementById('legend');
    if (legend) legend.classList.remove('hidden');
  } else {
    closePanel();
  }

  setCurrentView(view);

  // Update tab buttons
  document.querySelectorAll('#view-tabs button').forEach(btn => {
    btn.classList.toggle('active', btn.textContent.toLowerCase() === view);
  });

  // Update search placeholder
  const searchInput = document.getElementById('search');
  if (searchInput) {
    searchInput.placeholder = view === 'scripts' ? 'Search scripts...' : 'Search scenes...';
  }

  if (view === 'scenes') {
    loadSceneView();
  } else {
    updateStats();
    draw();
  }
};

async function loadSceneView() {
  // Request scene data from Godot
  try {
    const result = await sendCommand('map_scenes', { root: 'res://' });
    if (!result.error) {
      setSceneData(result.scene_map);
      updateStats();
      draw();
    } else {
      console.error('Failed to load scenes:', result.error);
      alert('Failed to load scenes: ' + (result.error || 'Unknown error'));
    }
  } catch (err) {
    console.error('Failed to load scenes:', err);
    // Show placeholder for now
    draw();
  }
}

// ---- Delete Script ----
let deleteTarget = null;

window.deleteScript = function () {
  contextMenu.classList.remove('visible');
  if (!rightClickedNode) return;

  deleteTarget = rightClickedNode;
  const scriptPath = deleteTarget.path;
  const scriptName = deleteTarget.filename;

  // Find references to this script in the project graph
  const refs = edges.filter(e => e.to === scriptPath || e.from === scriptPath);

  document.getElementById('delete-script-title').textContent = `Delete "${scriptName}"`;

  const infoEl = document.getElementById('delete-script-info');
  infoEl.innerHTML = `<div style="color:var(--text-muted);font-size:13px">${scriptPath}</div>`;

  const refsEl = document.getElementById('delete-script-refs');
  if (refs.length > 0) {
    refsEl.innerHTML = `<div style="color:#fab387;margin-bottom:8px">This script has ${refs.length} connection(s):</div>` +
      refs.map(e => {
        const other = e.from === scriptPath ? e.to : e.from;
        return `<div style="font-size:12px;color:var(--text-secondary);padding:2px 0">&bull; ${e.type}: ${other}</div>`;
      }).join('');
  } else {
    refsEl.innerHTML = '';
  }

  document.getElementById('delete-script-modal').style.display = 'flex';
};

function closeDeleteScriptModal() {
  document.getElementById('delete-script-modal').style.display = 'none';
  deleteTarget = null;
}
window.closeDeleteScriptModal = closeDeleteScriptModal;

window.confirmDeleteScript = async function () {
  if (!deleteTarget) return;

  const target = deleteTarget;
  const scriptPath = target.path;
  const scriptExtends = target.extends || 'Node';
  const scriptClassName = target.class_name || '';
  const scriptFilename = target.filename;

  const command = createCommand(
    `Delete script '${scriptFilename}'`,
    async () => {
      const result = await sendCommand('delete_script', { path: scriptPath });
      if (result.error) throw new Error(result.error || 'Unknown error');
      closePanel();
      await refreshProject();
    },
    async () => {
      const result = await sendCommand('create_script_file', {
        path: scriptPath, extends: scriptExtends, class_name: scriptClassName
      });
      if (result.error) throw new Error(result.error || 'Unknown error');
      await refreshProject();
    }
  );

  try {
    await undoManager.execute(command);
    closeDeleteScriptModal();
  } catch (err) {
    alert('Failed to delete script: ' + err.message);
  }

  deleteTarget = null;
};

// ---- Rename / Move Script ----
let usingRenameCustomFolder = false;

window.renameScript = function () {
  contextMenu.classList.remove('visible');
  if (!rightClickedNode) return;

  // Populate folder dropdown
  const folderSelect = document.getElementById('rename-script-folder');
  const folders = [...new Set(nodes.map(n => n.folder).filter(Boolean))].sort();
  const currentFolder = rightClickedNode.folder || rightClickedNode.path.substring(0, rightClickedNode.path.lastIndexOf('/') + 1);

  folderSelect.innerHTML = '';
  for (const folder of folders) {
    const opt = document.createElement('option');
    opt.value = folder;
    opt.textContent = folder.replace('res://', '');
    if (folder === currentFolder) opt.selected = true;
    folderSelect.appendChild(opt);
  }

  // Reset to dropdown mode
  usingRenameCustomFolder = false;
  folderSelect.style.display = '';
  document.getElementById('rename-script-custom-folder').style.display = 'none';

  // Pre-fill filename
  const filenameInput = document.getElementById('rename-script-filename');
  filenameInput.value = rightClickedNode.filename;

  document.getElementById('rename-script-modal').style.display = 'flex';
  filenameInput.focus();
  filenameInput.select();
};

window.toggleRenameCustomFolder = function () {
  usingRenameCustomFolder = !usingRenameCustomFolder;
  const folderSelect = document.getElementById('rename-script-folder');
  const customInput = document.getElementById('rename-script-custom-folder');
  folderSelect.style.display = usingRenameCustomFolder ? 'none' : '';
  customInput.style.display = usingRenameCustomFolder ? '' : 'none';
  if (usingRenameCustomFolder) {
    customInput.value = folderSelect.value || 'res://';
    customInput.focus();
  }
};

function closeRenameScriptModal() {
  document.getElementById('rename-script-modal').style.display = 'none';
}
window.closeRenameScriptModal = closeRenameScriptModal;

window.submitRenameScript = async function () {
  if (!rightClickedNode) return;

  const oldPath = rightClickedNode.path;
  let folder = usingRenameCustomFolder
    ? document.getElementById('rename-script-custom-folder').value.trim()
    : document.getElementById('rename-script-folder').value;
  let filename = document.getElementById('rename-script-filename').value.trim();
  const updateRefs = document.getElementById('rename-update-refs').checked;

  if (!folder) {
    alert('Please select a folder');
    return;
  }
  if (!filename) {
    alert('Please enter a filename');
    return;
  }
  if (!folder.startsWith('res://')) folder = 'res://' + folder;
  if (!folder.endsWith('/')) folder += '/';
  if (!filename.endsWith('.gd')) filename += '.gd';

  const newPath = folder + filename;

  if (newPath === oldPath) {
    closeRenameScriptModal();
    return;
  }

  const command = createCommand(
    `Rename script to '${filename}'`,
    async () => {
      const result = await sendCommand('rename_script', {
        old_path: oldPath, new_path: newPath, update_references: updateRefs
      });
      if (result.error) throw new Error(result.error || 'Unknown error');
      closePanel();
      await refreshProject();
    },
    async () => {
      const result = await sendCommand('rename_script', {
        old_path: newPath, new_path: oldPath, update_references: updateRefs
      });
      if (result.error) throw new Error(result.error || 'Unknown error');
      await refreshProject();
    }
  );

  try {
    await undoManager.execute(command);
    closeRenameScriptModal();
  } catch (err) {
    alert('Failed to rename script: ' + err.message);
  }

  rightClickedNode = null;
};

// ---- Connect Signal Dialog ----

let pendingConnect = null; // { sourceNode, signalName, targetNode, funcName }

export function showConnectDialog(sourceNode, signalName, targetNode, funcName) {
  pendingConnect = { sourceNode, signalName, targetNode, funcName };
  const isSame = sourceNode.path === targetNode.path;

  // Summary
  const summary = document.getElementById('connect-summary');
  summary.innerHTML = `<span style="color:#a6e3a1">signal</span> <strong>${signalName}</strong> → <span style="color:#89dceb">func</span> <strong>${funcName}</strong>` +
    (isSame ? '' : `<br><span style="font-size:11px;color:var(--text-muted)">${sourceNode.filename} → ${targetNode.filename}</span>`);

  // Reference input (cross-script only)
  const refRow = document.getElementById('connect-ref-row');
  const refInput = document.getElementById('connect-ref-input');
  if (isSame) {
    refRow.style.display = 'none';
  } else {
    refRow.style.display = '';
    // Try to guess the reference: look for a variable typed to target's class_name
    let guess = '$' + targetNode.filename.replace('.gd', '');
    if (targetNode.class_name) {
      const typedVar = sourceNode.variables && sourceNode.variables.find(v => v.type === targetNode.class_name);
      if (typedVar) guess = typedVar.name;
    }
    refInput.value = guess;
  }

  // Live preview update when reference changes
  refInput.oninput = updateConnectPreview;
  refInput.onkeydown = (e) => {
    if (e.key === 'Enter') { e.preventDefault(); window.confirmConnect(); }
    if (e.key === 'Escape') { e.preventDefault(); closeConnectModal(); }
  };

  updateConnectPreview();
  document.getElementById('connect-modal').style.display = 'flex';
  if (!isSame) refInput.focus();
}

function updateConnectPreview() {
  if (!pendingConnect) return;
  const { sourceNode, signalName, targetNode, funcName } = pendingConnect;
  const isSame = sourceNode.path === targetNode.path;
  const refInput = document.getElementById('connect-ref-input');
  const ref = isSame ? '' : (refInput ? refInput.value.trim() : '');

  const connectLine = isSame
    ? `${signalName}.connect(${funcName})`
    : `${signalName}.connect(${ref}.${funcName})`;

  const preview = document.getElementById('connect-preview');
  preview.innerHTML = `<span style="color:var(--text-muted)"># in _ready():</span>\n${connectLine}`;
}

function closeConnectModal() {
  document.getElementById('connect-modal').style.display = 'none';
  pendingConnect = null;
}
window.closeConnectModal = closeConnectModal;

window.confirmConnect = async function () {
  if (!pendingConnect) return;
  const { sourceNode, signalName, targetNode, funcName } = pendingConnect;
  const isSame = sourceNode.path === targetNode.path;
  const refInput = document.getElementById('connect-ref-input');
  const ref = isSame ? '' : (refInput ? refInput.value.trim() : '');

  if (!isSame && !ref) {
    alert('Please enter a target reference');
    return;
  }

  const connectLine = isSame
    ? `\t${signalName}.connect(${funcName})`
    : `\t${signalName}.connect(${ref}.${funcName})`;

  closeConnectModal();

  try {
    // Find _ready() in source node
    const readyFunc = sourceNode.functions ? sourceNode.functions.find(f => f.name === '_ready') : null;

    if (readyFunc && readyFunc.body) {
      const bodyLines = readyFunc.body.split('\n').filter(l => l.trim());
      if (bodyLines.length === 1 && bodyLines[0].trim() === 'pass') {
        // Replace 'pass' with connect line
        await sendCommand('edit_script', {
          edit: {
            type: 'snippet_replace',
            file: sourceNode.path,
            old_snippet: '\tpass',
            new_snippet: connectLine,
            context_before: 'func _ready()'
          }
        });
      } else {
        // Append after last line of _ready body
        const lastLine = bodyLines[bodyLines.length - 1];
        await sendCommand('edit_script', {
          edit: {
            type: 'snippet_replace',
            file: sourceNode.path,
            old_snippet: lastLine,
            new_snippet: lastLine + '\n' + connectLine,
            context_before: 'func _ready()'
          }
        });
      }
    } else {
      // No _ready() — create one. Insert before first function or at end.
      const firstFunc = sourceNode.functions && sourceNode.functions.length > 0
        ? sourceNode.functions[0] : null;
      if (firstFunc) {
        const funcDecl = `func ${firstFunc.name}(`;
        await sendCommand('edit_script', {
          edit: {
            type: 'snippet_replace',
            file: sourceNode.path,
            old_snippet: funcDecl,
            new_snippet: `func _ready() -> void:\n${connectLine}\n\n${funcDecl}`
          }
        });
      } else {
        // No functions at all — append to end of file by matching last signal or variable
        const lastSig = sourceNode.signals && sourceNode.signals.length > 0
          ? sourceNode.signals[sourceNode.signals.length - 1] : null;
        const anchor = lastSig
          ? `signal ${typeof lastSig === 'string' ? lastSig : lastSig.name}`
          : sourceNode.extends ? `extends ${sourceNode.extends}` : null;

        if (anchor) {
          // Find the full line to anchor on — just match the beginning
          await sendCommand('edit_script', {
            edit: {
              type: 'snippet_replace',
              file: sourceNode.path,
              old_snippet: anchor,
              new_snippet: anchor + `\n\n\nfunc _ready() -> void:\n${connectLine}`
            }
          });
        }
      }
    }

    // Optimistically add edge
    edges.push({
      from: sourceNode.path,
      to: targetNode.path,
      type: 'signal',
      signal_name: signalName
    });

    draw();
  } catch (err) {
    alert('Failed to inject .connect(): ' + err.message);
    console.error('Connect injection error:', err);
  }
};
