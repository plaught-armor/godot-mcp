/**
 * Detail panel, inline editing, function viewer, and section management
 */

import {
  nodes, edges, selectedNode, setSelectedNode, esc,
  selectedSceneNode, setSelectedSceneNode,
  sceneNodeProperties, setSceneNodeProperties,
  expandedScene, scriptToScenes,
  connectionDrag, setConnectionDrag
} from './state.js';
import { sendCommand } from './websocket.js';
import { highlightGDScript } from './syntax.js';
import { draw, screenToWorld, getCanvas, hitTest, portHitTest } from './canvas.js';
import { undoManager, createCommand } from './undo.js';

let detailPanel;
let currentPanelMode = 'script'; // 'script' or 'sceneNode'

// ---- Godot Type List for Combobox ----
const GODOT_TYPES = [
  // Primitives
  'bool', 'int', 'float', 'String', 'StringName', 'NodePath',
  // Math
  'Vector2', 'Vector2i', 'Vector3', 'Vector3i', 'Vector4', 'Vector4i',
  'Rect2', 'Rect2i', 'AABB',
  'Transform2D', 'Transform3D', 'Basis', 'Projection', 'Quaternion', 'Plane',
  // Color
  'Color',
  // Collections
  'Array', 'Dictionary',
  // Packed arrays
  'PackedByteArray', 'PackedInt32Array', 'PackedInt64Array',
  'PackedFloat32Array', 'PackedFloat64Array',
  'PackedStringArray', 'PackedVector2Array', 'PackedVector3Array',
  'PackedVector4Array', 'PackedColorArray',
  // Resources
  'Resource', 'Texture2D', 'Texture3D', 'Material', 'Mesh', 'Font',
  'AudioStream', 'PackedScene', 'Script', 'Shader', 'Theme',
  'StyleBox', 'SpriteFrames', 'TileSet', 'Curve', 'Gradient',
  'Image', 'BitMap', 'Animation', 'AnimationLibrary',
  // Common nodes
  'Node', 'Node2D', 'Node3D', 'Control',
  'CharacterBody2D', 'CharacterBody3D',
  'RigidBody2D', 'RigidBody3D',
  'StaticBody2D', 'StaticBody3D',
  'Area2D', 'Area3D',
  'Sprite2D', 'Sprite3D', 'AnimatedSprite2D', 'AnimatedSprite3D',
  'Camera2D', 'Camera3D',
  'CollisionShape2D', 'CollisionShape3D',
  'RayCast2D', 'RayCast3D',
  'Timer', 'AudioStreamPlayer', 'AudioStreamPlayer2D', 'AudioStreamPlayer3D',
  'Label', 'Button', 'TextureRect', 'LineEdit', 'TextEdit',
  'Panel', 'HBoxContainer', 'VBoxContainer', 'GridContainer', 'MarginContainer',
  'TileMapLayer', 'NavigationAgent2D', 'NavigationAgent3D',
  'GPUParticles2D', 'GPUParticles3D', 'CPUParticles2D', 'CPUParticles3D',
  // Other
  'Object', 'RefCounted', 'Callable', 'Signal', 'RID',
  'Tween', 'InputEvent', 'InputEventKey', 'InputEventMouseButton',
];

const TYPE_DEFAULTS = {
  'bool': 'false', 'int': '0', 'float': '0.0',
  'String': '""', 'StringName': '&""', 'NodePath': '@""',
  'Vector2': 'Vector2.ZERO', 'Vector2i': 'Vector2i.ZERO',
  'Vector3': 'Vector3.ZERO', 'Vector3i': 'Vector3i.ZERO',
  'Vector4': 'Vector4.ZERO', 'Vector4i': 'Vector4i.ZERO',
  'Rect2': 'Rect2()', 'Rect2i': 'Rect2i()', 'AABB': 'AABB()',
  'Transform2D': 'Transform2D.IDENTITY', 'Transform3D': 'Transform3D.IDENTITY',
  'Basis': 'Basis.IDENTITY', 'Projection': 'Projection()',
  'Quaternion': 'Quaternion.IDENTITY', 'Plane': 'Plane()',
  'Color': 'Color.WHITE',
  'Array': '[]', 'Dictionary': '{}',
  'PackedByteArray': 'PackedByteArray()', 'PackedInt32Array': 'PackedInt32Array()',
  'PackedInt64Array': 'PackedInt64Array()', 'PackedFloat32Array': 'PackedFloat32Array()',
  'PackedFloat64Array': 'PackedFloat64Array()', 'PackedStringArray': 'PackedStringArray()',
  'PackedVector2Array': 'PackedVector2Array()', 'PackedVector3Array': 'PackedVector3Array()',
  'PackedVector4Array': 'PackedVector4Array()', 'PackedColorArray': 'PackedColorArray()',
  'Callable': 'Callable()', 'Signal': 'Signal()', 'RID': 'RID()',
};

// ---- Searchable Type Combobox ----
let comboboxEl = null;
let comboboxInput = null;
let comboboxList = null;
let comboboxTrigger = null;
let comboboxHighlightIdx = 0;
let comboboxItems = []; // currently displayed items (flat array of type strings)

function ensureCombobox() {
  if (comboboxEl) return;
  comboboxEl = document.createElement('div');
  comboboxEl.id = 'type-combobox';
  comboboxEl.style.display = 'none';
  comboboxEl.innerHTML = `<input type="text" id="type-combobox-input" placeholder="Search types..." autocomplete="off" /><ul id="type-combobox-list"></ul>`;
  document.body.appendChild(comboboxEl);
  comboboxInput = comboboxEl.querySelector('input');
  comboboxList = comboboxEl.querySelector('ul');

  comboboxInput.addEventListener('input', () => filterCombobox(comboboxInput.value));
  comboboxInput.addEventListener('keydown', handleComboboxKey);
  // Close on outside click
  document.addEventListener('mousedown', (e) => {
    if (comboboxEl.style.display !== 'none' && !comboboxEl.contains(e.target) && e.target !== comboboxTrigger) {
      closeCombobox(false);
    }
  });
}

function openTypeCombobox(triggerEl) {
  ensureCombobox();
  comboboxTrigger = triggerEl;

  // Collect project types from nodes
  const projectTypes = [...new Set(nodes.filter(n => n.class_name).map(n => n.class_name))].sort();
  const builtinSet = new Set(GODOT_TYPES);
  // Remove project types that duplicate built-ins
  const uniqueProjectTypes = projectTypes.filter(t => !builtinSet.has(t));

  const currentType = triggerEl.textContent.trim();
  comboboxInput.value = currentType;

  // Position below the trigger
  const rect = triggerEl.getBoundingClientRect();
  comboboxEl.style.display = 'flex';
  comboboxEl.style.left = rect.left + 'px';
  comboboxEl.style.top = (rect.bottom + 4) + 'px';

  // Ensure it doesn't go off-screen right
  requestAnimationFrame(() => {
    const cbRect = comboboxEl.getBoundingClientRect();
    if (cbRect.right > window.innerWidth - 8) {
      comboboxEl.style.left = Math.max(8, window.innerWidth - cbRect.width - 8) + 'px';
    }
    if (cbRect.bottom > window.innerHeight - 8) {
      comboboxEl.style.top = (rect.top - cbRect.height - 4) + 'px';
    }
  });

  // Store section data for rendering
  comboboxEl._projectTypes = uniqueProjectTypes;
  comboboxEl._builtinTypes = GODOT_TYPES;
  comboboxEl._currentType = currentType;

  filterCombobox(currentType);
  comboboxInput.focus();
  comboboxInput.select();
}

function filterCombobox(query) {
  const q = query.toLowerCase();
  const projectTypes = comboboxEl._projectTypes || [];
  const builtinTypes = comboboxEl._builtinTypes || GODOT_TYPES;
  const currentType = comboboxEl._currentType || '';

  const filteredProject = q ? projectTypes.filter(t => t.toLowerCase().includes(q)) : projectTypes;
  const filteredBuiltin = q ? builtinTypes.filter(t => t.toLowerCase().includes(q)) : builtinTypes;

  let html = '';
  comboboxItems = [];

  if (filteredProject.length > 0) {
    html += `<li class="section-header">Project</li>`;
    for (const t of filteredProject) {
      const isCurrent = t === currentType;
      comboboxItems.push(t);
      html += `<li class="type-item${isCurrent ? ' current' : ''}" data-type="${esc(t)}">${esc(t)}</li>`;
    }
  }

  if (filteredBuiltin.length > 0) {
    html += `<li class="section-header">Built-in</li>`;
    for (const t of filteredBuiltin) {
      const isCurrent = t === currentType;
      comboboxItems.push(t);
      html += `<li class="type-item${isCurrent ? ' current' : ''}" data-type="${esc(t)}">${esc(t)}</li>`;
    }
  }

  // Custom type option if query doesn't match anything exactly
  if (q && !comboboxItems.some(t => t.toLowerCase() === q)) {
    html += `<li class="type-item custom-type" data-type="${esc(query)}">Use: <strong>${esc(query)}</strong></li>`;
    comboboxItems.push(query);
  }

  comboboxList.innerHTML = html;
  comboboxHighlightIdx = 0;
  updateComboboxHighlight();

  // Click handlers
  comboboxList.querySelectorAll('.type-item').forEach(li => {
    li.addEventListener('mousedown', (e) => {
      e.preventDefault();
      selectComboboxType(li.dataset.type);
    });
  });
}

function updateComboboxHighlight() {
  comboboxList.querySelectorAll('.type-item').forEach((li, i) => {
    li.classList.toggle('highlighted', i === comboboxHighlightIdx);
  });
  // Scroll highlighted into view
  const highlighted = comboboxList.querySelector('.type-item.highlighted');
  if (highlighted) highlighted.scrollIntoView({ block: 'nearest' });
}

function handleComboboxKey(e) {
  const itemCount = comboboxItems.length;
  if (e.key === 'ArrowDown') {
    e.preventDefault();
    comboboxHighlightIdx = (comboboxHighlightIdx + 1) % itemCount;
    updateComboboxHighlight();
  } else if (e.key === 'ArrowUp') {
    e.preventDefault();
    comboboxHighlightIdx = (comboboxHighlightIdx - 1 + itemCount) % itemCount;
    updateComboboxHighlight();
  } else if (e.key === 'Enter') {
    e.preventDefault();
    if (comboboxItems.length > 0) {
      selectComboboxType(comboboxItems[comboboxHighlightIdx]);
    }
  } else if (e.key === 'Escape') {
    e.preventDefault();
    closeCombobox(false);
  } else if (e.key === 'Tab') {
    e.preventDefault();
    if (comboboxItems.length > 0) {
      selectComboboxType(comboboxItems[comboboxHighlightIdx]);
    } else {
      closeCombobox(false);
    }
  }
}

function selectComboboxType(type) {
  if (!comboboxTrigger) return;

  // Fork: param-type triggers save signal params instead of variable type
  if (comboboxTrigger.classList.contains('param-type')) {
    comboboxTrigger.textContent = type;
    const editor = comboboxTrigger.closest('.signal-params-editor');
    const trigger = comboboxTrigger;
    closeCombobox(false);
    if (editor) saveSignalParamsFromEditor(editor);
    // If this is the last param, Tab-like behavior: add a new param
    const rows = editor ? editor.querySelectorAll('.param-row') : [];
    const thisRow = trigger.closest('.param-row');
    if (editor && thisRow === rows[rows.length - 1]) {
      addParam(editor, true);
    }
    return;
  }

  const oldValue = comboboxTrigger.dataset.original || '';
  if (type === oldValue) {
    closeCombobox(false);
    return;
  }

  comboboxTrigger.textContent = type;

  // Trigger save through the same undo-wrapped flow as handleInlineEdit
  const li = comboboxTrigger.closest('li');
  if (!li) { closeCombobox(false); return; }

  const isExport = li.dataset.exported === 'true';
  const index = parseInt(li.dataset.varIndex);
  const nodePath = selectedNode.path;

  const vars = selectedNode.variables.filter(v => v.exported === isExport);
  const v = vars[index];
  if (!v) { closeCombobox(false); return; }

  const actualIndex = selectedNode.variables.findIndex(vr => vr.name === v.name);
  if (actualIndex === -1) { closeCombobox(false); return; }

  const oldVar = { ...selectedNode.variables[actualIndex] };
  const newVar = { ...oldVar, type: type };

  // Auto-fill default if empty or was previous type's zero-value
  const oldTypeDefault = TYPE_DEFAULTS[oldVar.type] || '';
  const currentDefault = oldVar.default || '';
  if (!currentDefault || currentDefault === oldTypeDefault) {
    const newDefault = TYPE_DEFAULTS[type] || '';
    newVar.default = newDefault;
  }

  const command = createCommand(
    `Set type '${type}' on '${v.name}'`,
    async () => {
      await sendCommand('modify_variable', {
        path: nodePath, action: 'update', old_name: oldVar.name,
        name: newVar.name, type: newVar.type, default: newVar.default, exported: isExport
      });
      const node = nodes.find(n => n.path === nodePath) || selectedNode;
      const ai = node.variables.findIndex(vr => vr.name === oldVar.name);
      if (ai !== -1) node.variables[ai] = { ...newVar };
      if (selectedNode && selectedNode.path === nodePath) openPanel(selectedNode);
    },
    async () => {
      await sendCommand('modify_variable', {
        path: nodePath, action: 'update', old_name: newVar.name,
        name: oldVar.name, type: oldVar.type, default: oldVar.default, exported: isExport
      });
      const node = nodes.find(n => n.path === nodePath) || selectedNode;
      const ai = node.variables.findIndex(vr => vr.name === newVar.name);
      if (ai !== -1) node.variables[ai] = { ...oldVar };
      if (selectedNode && selectedNode.path === nodePath) openPanel(selectedNode);
    }
  );

  undoManager.execute(command).then(() => {
    if (comboboxTrigger) comboboxTrigger.dataset.original = type;
  }).catch(err => {
    if (comboboxTrigger) comboboxTrigger.textContent = oldValue;
    console.error('Failed to set type:', err);
  });

  closeCombobox(false);
}

function closeCombobox(save) {
  if (!comboboxEl) return;
  comboboxEl.style.display = 'none';
  comboboxTrigger = null;
  comboboxItems = [];
}

// ---- Signal Param Helpers ----
function parseParams(paramStr) {
  if (!paramStr || !paramStr.trim()) return [];
  return paramStr.split(',').map(p => {
    const parts = p.trim().split(':').map(s => s.trim());
    return { name: parts[0] || '', type: parts[1] || '' };
  }).filter(p => p.name);
}

function serializeParams(params) {
  return params.map(p => p.type ? `${p.name}: ${p.type}` : p.name).join(', ');
}

function renderParamEditor(sigParams, signalIndex) {
  const params = parseParams(sigParams);
  let html = `<span class="signal-params-editor" data-signal-index="${signalIndex}" data-original="${esc(sigParams)}">`;
  for (let pi = 0; pi < params.length; pi++) {
    html += `<span class="param-row">`;
    html += `<input class="param-name" value="${esc(params[pi].name)}" placeholder="name" spellcheck="false" />`;
    html += `<span class="param-colon">:</span>`;
    html += `<span class="tp param-type combobox-trigger" data-placeholder="Type">${esc(params[pi].type)}</span>`;
    html += `<button class="param-delete" title="Remove">×</button>`;
    html += `</span>`;
  }
  html += `<button class="param-add" title="Add parameter">+</button>`;
  html += `</span>`;
  return html;
}

function initParamEditors() {
  document.querySelectorAll('.signal-params-editor').forEach(editor => {
    // Add param button
    editor.querySelector('.param-add').addEventListener('click', () => addParam(editor));

    // Delete buttons
    editor.querySelectorAll('.param-delete').forEach(btn => {
      btn.addEventListener('click', () => {
        btn.closest('.param-row').remove();
        saveSignalParamsFromEditor(editor);
      });
    });

    // Name input blur → save
    editor.querySelectorAll('.param-name').forEach(input => {
      input.addEventListener('blur', () => saveSignalParamsFromEditor(editor));
      input.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === 'Tab') {
          e.preventDefault();
          // Focus the type trigger next to this name
          const row = input.closest('.param-row');
          const typeTrigger = row.querySelector('.param-type');
          if (typeTrigger) openTypeCombobox(typeTrigger);
        }
        if (e.key === 'Escape') {
          input.blur();
        }
      });
    });

    // Type combobox triggers
    editor.querySelectorAll('.param-type').forEach(el => {
      el.addEventListener('click', () => openTypeCombobox(el));
    });
  });
}

function addParam(editor, focus = true) {
  const addBtn = editor.querySelector('.param-add');
  const row = document.createElement('span');
  row.className = 'param-row';
  row.innerHTML = `<input class="param-name" value="" placeholder="name" spellcheck="false" /><span class="param-colon">:</span><span class="tp param-type combobox-trigger" data-placeholder="Type"></span><button class="param-delete" title="Remove">×</button>`;
  editor.insertBefore(row, addBtn);

  // Wire events
  const input = row.querySelector('.param-name');
  const deleteBtn = row.querySelector('.param-delete');
  const typeTrigger = row.querySelector('.param-type');

  deleteBtn.addEventListener('click', () => {
    row.remove();
    saveSignalParamsFromEditor(editor);
  });

  input.addEventListener('blur', () => saveSignalParamsFromEditor(editor));
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === 'Tab') {
      e.preventDefault();
      if (typeTrigger) openTypeCombobox(typeTrigger);
    }
    if (e.key === 'Escape') input.blur();
  });

  typeTrigger.addEventListener('click', () => openTypeCombobox(typeTrigger));

  if (focus) {
    input.focus();
  }
}

function collectParamsFromEditor(editor) {
  const params = [];
  editor.querySelectorAll('.param-row').forEach(row => {
    const name = row.querySelector('.param-name').value.trim();
    const type = row.querySelector('.param-type').textContent.trim();
    if (name) params.push({ name, type });
  });
  return params;
}

function saveSignalParamsFromEditor(editor) {
  const signalIndex = parseInt(editor.dataset.signalIndex);
  const oldParamsStr = editor.dataset.original || '';
  const newParams = collectParamsFromEditor(editor);
  const newParamsStr = serializeParams(newParams);

  if (newParamsStr === oldParamsStr) return;

  const sig = selectedNode.signals[signalIndex];
  const sigName = typeof sig === 'string' ? sig : sig.name;
  const nodePath = selectedNode.path;

  const command = createCommand(
    `Update params on '${sigName}'`,
    async () => {
      await sendCommand('modify_signal', {
        path: nodePath, action: 'update',
        old_name: sigName, name: sigName, params: newParamsStr
      });
      const node = nodes.find(n => n.path === nodePath) || selectedNode;
      node.signals[signalIndex] = { name: sigName, params: newParamsStr };
    },
    async () => {
      await sendCommand('modify_signal', {
        path: nodePath, action: 'update',
        old_name: sigName, name: sigName, params: oldParamsStr
      });
      const node = nodes.find(n => n.path === nodePath) || selectedNode;
      node.signals[signalIndex] = { name: sigName, params: oldParamsStr };
      if (selectedNode && selectedNode.path === nodePath) openPanel(selectedNode);
    }
  );

  undoManager.execute(command).then(() => {
    editor.dataset.original = newParamsStr;
  }).catch(err => {
    console.error('Failed to update signal params:', err);
  });
}

// ---- Connection Drag (signal → function) ----

function initConnectionDrag() {
  const handles = document.querySelectorAll('.connection-drag-handle');
  for (const handle of handles) {
    handle.addEventListener('mousedown', onConnectionDragStart);
  }
}

function onConnectionDragStart(e) {
  e.preventDefault();
  e.stopPropagation();
  if (!selectedNode) return;

  const handle = e.currentTarget;
  const sigName = handle.dataset.signalName;
  const sigParams = handle.dataset.signalParams || '';

  setConnectionDrag({
    signalName: sigName,
    signalParams: sigParams,
    sourceNode: selectedNode,
    cursorX: e.clientX,
    cursorY: e.clientY,
    targetNode: null,
    hoveredPort: -1
  });

  // Add drop-target class to function items in the same panel (same-script shortcut)
  const funcItems = document.querySelectorAll('.func-item');
  for (const item of funcItems) {
    item.classList.add('connection-drop-target');
  }

  document.body.style.cursor = 'crosshair';

  // Document-level handlers for the drag duration
  document.addEventListener('mousemove', onConnectionDragMove);
  document.addEventListener('mouseup', onConnectionDragEnd);
}

function onConnectionDragMove(e) {
  if (!connectionDrag) return;
  connectionDrag.cursorX = e.clientX;
  connectionDrag.cursorY = e.clientY;

  // Hit test for target node and function port on canvas
  const w = screenToWorld(e.clientX, e.clientY);
  const hit = hitTest(w.x, w.y);
  // Allow same-node targeting (self-connect) and cross-node
  if (hit && hit.functions && hit.functions.length > 0) {
    connectionDrag.targetNode = hit;
    connectionDrag.hoveredPort = portHitTest(w.x, w.y, hit);
  } else {
    connectionDrag.targetNode = null;
    connectionDrag.hoveredPort = -1;
  }

  draw();
}

function onConnectionDragEnd(e) {
  if (!connectionDrag) return;

  document.removeEventListener('mousemove', onConnectionDragMove);
  document.removeEventListener('mouseup', onConnectionDragEnd);
  document.body.style.cursor = '';

  // Remove drop-target classes
  const funcItems = document.querySelectorAll('.connection-drop-target');
  for (const item of funcItems) {
    item.classList.remove('connection-drop-target');
  }

  // Check if dropped on a panel function item (same-script)
  const target = e.target.closest('.func-item.connection-drop-target');
  if (target && selectedNode) {
    const funcName = target.dataset.funcName;
    if (funcName) {
      const drag = connectionDrag;
      setConnectionDrag(null);
      draw();
      // Fire the connection dialog for same-script
      import('./modals.js').then(m => {
        m.showConnectDialog(drag.sourceNode, drag.signalName, drag.sourceNode, funcName);
      });
      return;
    }
  }

  // Check if dropped on a canvas function port (cross-script) — handled by events.js
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

  // Cancelled — dropped on empty space
  setConnectionDrag(null);
  draw();
}

export function initPanel() {
  detailPanel = document.getElementById('detail-panel');
  initPanelResizing();
}

export function openPanel(node) {
  setSelectedNode(node);

  document.getElementById('panel-title').textContent = node.class_name || node.filename.replace('.gd', '');
  document.getElementById('panel-path').textContent = node.path;

  let html = '';

  // Description
  if (node.description) {
    html += `<div class="desc-block">${esc(node.description)}</div>`;
  }

  // Meta badges
  html += `<div class="meta-row">`;
  html += `<div class="meta-badge"><span>${node.line_count}</span> lines</div>`;
  html += `<div class="meta-badge">extends <span>${node.extends || 'Node'}</span></div>`;
  if (node.class_name) html += `<div class="meta-badge">class <span>${esc(node.class_name)}</span></div>`;
  html += `</div>`;
  
  // Scene usage (if this script is used in scenes)
  const usedInScenes = scriptToScenes[node.path];
  if (usedInScenes && usedInScenes.length > 0) {
    html += `<div class="section scene-usage-section">`;
    html += `<div class="section-header">Used in Scenes <span class="section-count">${usedInScenes.length}</span></div>`;
    html += `<ul class="item-list scene-list">`;
    for (const scene of usedInScenes) {
      html += `<li class="scene-link" onclick="jumpToScene('${esc(scene.path)}')">`;
      html += `<span class="scene-icon">📦</span>`;
      html += `<span class="scene-name">${esc(scene.name)}</span>`;
      html += `</li>`;
    }
    html += `</ul>`;
    html += `</div>`;
  }

  // Variables - split into @export and regular
  const exportVars = (node.variables || []).filter(v => v.exported);
  const regularVars = (node.variables || []).filter(v => !v.exported);

  // Exports section (always show for adding)
  html += `<div class="section">`;
  html += `<div class="section-header">Exports <span class="section-count">${exportVars.length}</span></div>`;
  html += `<ul class="item-list" id="exports-list">`;
  for (let vi = 0; vi < exportVars.length; vi++) {
    const v = exportVars[vi];
    html += `<li data-var-index="${vi}" data-exported="true">`;
    html += `<span class="exp">@export</span> `;
    html += `<span class="kw">var</span> `;
    html += `<span class="editable var-name" contenteditable="true" data-field="name" data-original="${esc(v.name)}">${esc(v.name)}</span>`;
    html += `<span class="ret">:</span> `;
    html += `<span class="tp var-type combobox-trigger" data-field="type" data-placeholder="Type" data-original="${esc(v.type || '')}">${esc(v.type || '')}</span>`;
    html += ` <span class="ret">=</span> `;
    html += `<span class="num editable var-default" contenteditable="true" data-field="default" data-placeholder="value" data-original="${esc(v.default || '')}">${esc(v.default || '')}</span>`;
    html += `<span class="item-actions">`;
    html += `<button class="delete" onclick="showDeleteUsages(${vi}, true, 'variable')" title="Delete">×</button>`;
    html += `</span>`;
    html += `</li>`;
  }
  html += `</ul>`;
  html += `<div class="add-item-btn" onclick="addNewVariable(true)">`;
  html += `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14M5 12h14"/></svg>`;
  html += `Add export</div>`;
  html += `</div>`;

  // Variables section (always show for adding)
  html += `<div class="section">`;
  html += `<div class="section-header">Variables <span class="section-count">${regularVars.length}</span></div>`;
  html += `<ul class="item-list" id="vars-list">`;
  for (let vi = 0; vi < regularVars.length; vi++) {
    const v = regularVars[vi];
    html += `<li data-var-index="${vi}" data-exported="false" data-onready="${v.onready || false}">`;
    if (v.onready) {
      html += `<span class="onready-badge" onclick="toggleOnready(${vi}, false)" title="Click to toggle @onready">@onready</span>`;
    }
    html += `<span class="kw">var</span> `;
    html += `<span class="editable var-name" contenteditable="true" data-field="name" data-original="${esc(v.name)}">${esc(v.name)}</span>`;
    html += `<span class="ret">:</span> `;
    html += `<span class="tp var-type combobox-trigger" data-field="type" data-placeholder="Type" data-original="${esc(v.type || '')}">${esc(v.type || '')}</span>`;
    html += ` <span class="ret">=</span> `;
    html += `<span class="num editable var-default" contenteditable="true" data-field="default" data-placeholder="value" data-original="${esc(v.default || '')}">${esc(v.default || '')}</span>`;
    html += `<span class="item-actions">`;
    if (!v.onready) {
      html += `<button onclick="toggleOnready(${vi}, false)" title="Add @onready" style="font-size:9px;width:auto;padding:0 4px;">⏱</button>`;
    }
    html += `<button class="delete" onclick="showDeleteUsages(${vi}, false, 'variable')" title="Delete">×</button>`;
    html += `</span>`;
    html += `</li>`;
  }
  html += `</ul>`;
  html += `<div class="add-item-btn" onclick="addNewVariable(false)">`;
  html += `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14M5 12h14"/></svg>`;
  html += `Add variable</div>`;
  html += `</div>`;

  // Functions
  if ((node.functions || []).length > 0) {
    html += `<div class="section">`;
    html += `<div class="section-header">Functions <span class="section-count">${node.functions.length}</span></div>`;
    html += `<ul class="item-list">`;
    for (let fi = 0; fi < node.functions.length; fi++) {
      const f = node.functions[fi];
      html += `<li class="clickable func-item" data-func-index="${fi}" data-func-name="${esc(f.name)}" onclick="toggleFunc(${fi})">`;

      html += `<span class="kw">func</span> <span class="fn">${esc(f.name)}</span>`;
      html += `<span class="param">(${esc(f.params)})</span>`;
      if (f.return_type) html += ` <span class="ret">&rarr;</span> <span class="tp">${esc(f.return_type)}</span>`;
      html += `<span style="margin-left:auto;display:flex;gap:4px;align-items:center">`;
      if (f.body_lines) html += `<span class="tag tag-lines">${f.body_lines}L</span>`;
      html += `<button class="delete" onclick="event.stopPropagation();showDeleteUsages(${fi}, false, 'function')" title="Delete function" style="opacity:0">×</button>`;
      html += `</span>`;
      html += `</li>`;
      html += `<div id="func-viewer-${fi}" class="func-viewer" style="display:none"></div>`;
    }
    html += `</ul></div>`;
  }

  // Signals section (always show for adding)
  const signalsList = node.signals || [];
  html += `<div class="section">`;
  html += `<div class="section-header">Signals <span class="section-count">${signalsList.length}</span></div>`;
  html += `<ul class="item-list" id="signals-list">`;
  for (let si = 0; si < signalsList.length; si++) {
    const s = signalsList[si];
    const sigName = typeof s === 'string' ? s : s.name;
    const sigParams = typeof s === 'object' ? s.params : '';
    html += `<li data-signal-index="${si}">`;
    html += `<span class="kw">signal</span> `;
    html += `<span class="sig editable signal-name" contenteditable="true" data-field="name" data-original="${esc(sigName)}">${esc(sigName)}</span>`;
    html += `<span class="param">(</span>`;
    html += renderParamEditor(sigParams, si);
    html += `<span class="param">)</span>`;
    html += `<span class="item-actions">`;
    html += `<span class="connection-drag-handle" data-signal-index="${si}" data-signal-name="${esc(sigName)}" data-signal-params="${esc(sigParams)}" title="Drag to connect">⊙</span>`;
    html += `<button class="delete" onclick="showDeleteUsages(${si}, false, 'signal')" title="Delete">×</button>`;
    html += `</span>`;
    html += `</li>`;
  }
  html += `</ul>`;
  html += `<div class="add-item-btn" onclick="addNewSignal()">`;
  html += `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14M5 12h14"/></svg>`;
  html += `Add signal</div>`;
  html += `</div>`;

  // Connections - group by target and show signal names
  const related = edges.filter(e => e.from === node.path || e.to === node.path);
  if (related.length > 0) {
    // Group connections by target and type
    const connGroups = {};
    for (const e of related) {
      const other = e.from === node.path ? e.to : e.from;
      const dir = e.from === node.path ? 'out' : 'in';
      const key = `${other}-${e.type}-${dir}`;
      if (!connGroups[key]) {
        connGroups[key] = { other, type: e.type, dir, signals: [] };
      }
      if (e.signal_name) connGroups[key].signals.push(e.signal_name);
    }

    html += `<div class="section">`;
    html += `<div class="section-header">Connections <span class="section-count">${related.length}</span></div>`;
    html += `<ul class="item-list">`;

    for (const key of Object.keys(connGroups)) {
      const g = connGroups[key];
      const dirIcon = g.dir === 'out' ? '→' : '←';
      const color = g.type === 'extends' ? 'var(--edge-extends)' : g.type === 'preload' ? 'var(--edge-preload)' : 'var(--edge-signal)';
      const filename = g.other.split('/').pop();

      html += `<li style="flex-wrap:wrap">`;
      html += `${dirIcon} <span style="color:${color}">${esc(filename)}</span> <span class="ret">(${g.type})</span>`;

      // Show signal names if this is a signal connection
      if (g.type === 'signal' && g.signals.length > 0) {
        const uniqueSignals = [...new Set(g.signals)];
        html += `<div style="width:100%;margin-top:4px;padding-left:20px;font-size:11px;color:var(--text-muted)">`;
        html += uniqueSignals.map(s => `<span class="sig">${esc(s)}</span>`).join(', ');
        html += `</div>`;
      }
      html += `</li>`;
    }
    html += `</ul></div>`;
  }

  // Preloads
  if ((node.preloads || []).length > 0) {
    html += `<div class="section">`;
    html += `<div class="section-header">Preloads <span class="section-count">${node.preloads.length}</span></div>`;
    html += `<ul class="item-list">`;
    for (const p of node.preloads) {
      html += `<li><span class="str">"${esc(p)}"</span></li>`;
    }
    html += `</ul></div>`;
  }

  document.getElementById('panel-body').innerHTML = html;
  detailPanel.classList.add('open');
  initSectionResizing();
  initInlineEditing();
  initParamEditors();
  initConnectionDrag();
  draw();
}

export function closePanel() {
  setSelectedNode(null);
  detailPanel.classList.remove('open');
  draw();
}

// Make closePanel available globally for onclick
window.closePanel = closePanel;

// Toggle function body viewer with inline editing
window.toggleFunc = function (fi) {
  const viewer = document.getElementById(`func-viewer-${fi}`);
  if (!viewer) return;

  if (viewer.style.display !== 'none') {
    viewer.style.display = 'none';
    viewer.innerHTML = '';
    return;
  }

  const f = selectedNode.functions[fi];
  if (!f.body) return;

  const editorId = `code-editor-${fi}`;

  viewer.innerHTML = `
    <div class="func-viewer-header">
      <span><span class="func-title">${esc(f.name)}</span> · <span id="line-count-${fi}">${f.body.split('\n').length}</span> lines</span>
      <button class="func-viewer-close" onclick="toggleFunc(${fi})">&times;</button>
    </div>
    <div class="func-viewer-code">
      <div class="code-editor-container" id="${editorId}">
        <div class="code-editor-highlight" id="highlight-${fi}"></div>
        <textarea class="code-editor-textarea" id="textarea-${fi}" spellcheck="false"></textarea>
      </div>
    </div>
    <div class="func-viewer-footer">
      <span class="status" id="status-${fi}">Modified</span>
      <span style="display:flex;gap:8px;align-items:center">
        <span style="opacity:0.6">Ctrl+S to save</span>
        <button class="save-btn" id="save-btn-${fi}" onclick="saveFunction(${fi})">Save</button>
      </span>
    </div>
  `;

  const textarea = document.getElementById(`textarea-${fi}`);
  const highlight = document.getElementById(`highlight-${fi}`);
  const statusEl = document.getElementById(`status-${fi}`);
  const saveBtn = document.getElementById(`save-btn-${fi}`);
  const lineCountEl = document.getElementById(`line-count-${fi}`);

  // Store original code for comparison
  textarea.dataset.original = f.body;
  textarea.dataset.funcIndex = fi;
  textarea.dataset.scriptPath = selectedNode.path;
  textarea.dataset.funcName = f.name;
  textarea.value = f.body;

  // Initial highlight
  updateHighlight(fi);

  // Sync highlight on input
  textarea.addEventListener('input', () => {
    updateHighlight(fi);
    const modified = textarea.value !== textarea.dataset.original;
    statusEl.classList.toggle('visible', modified);
    saveBtn.classList.toggle('active', modified);
    lineCountEl.textContent = textarea.value.split('\n').length;
  });

  // Sync scroll
  textarea.addEventListener('scroll', () => {
    highlight.style.transform = `translate(-${textarea.scrollLeft}px, -${textarea.scrollTop}px)`;
  });

  // Handle tab key
  textarea.addEventListener('keydown', (e) => {
    if (e.key === 'Tab') {
      e.preventDefault();
      const start = textarea.selectionStart;
      const end = textarea.selectionEnd;
      textarea.value = textarea.value.substring(0, start) + '\t' + textarea.value.substring(end);
      textarea.selectionStart = textarea.selectionEnd = start + 1;
      textarea.dispatchEvent(new Event('input'));
    }
    // Ctrl+S to save
    if (e.key === 's' && (e.ctrlKey || e.metaKey)) {
      e.preventDefault();
      saveFunction(fi);
    }
  });

  // Auto-resize textarea height
  function autoResize() {
    textarea.style.height = 'auto';
    textarea.style.height = textarea.scrollHeight + 'px';
    highlight.style.height = textarea.scrollHeight + 'px';
  }
  textarea.addEventListener('input', autoResize);
  setTimeout(autoResize, 0);

  viewer.style.display = 'block';
};

// Update syntax highlighting
function updateHighlight(fi) {
  const textarea = document.getElementById(`textarea-${fi}`);
  const highlight = document.getElementById(`highlight-${fi}`);
  if (!textarea || !highlight) return;

  // Highlight each line, wrap in spans for line-level highlighting
  const lines = textarea.value.split('\n');
  highlight.innerHTML = lines.map((line, i) =>
    `<div class="code-line" data-line="${i}">${highlightGDScript(line) || ' '}</div>`
  ).join('');
}

// Save function changes back to Godot
window.saveFunction = async function (fi) {
  const textarea = document.getElementById(`textarea-${fi}`);
  const statusEl = document.getElementById(`status-${fi}`);
  const saveBtn = document.getElementById(`save-btn-${fi}`);

  if (!textarea || textarea.value === textarea.dataset.original) return;

  const scriptPath = textarea.dataset.scriptPath;
  const funcName = textarea.dataset.funcName;
  const funcIndex = parseInt(textarea.dataset.funcIndex);
  const oldBody = textarea.dataset.original;
  const newCode = textarea.value;
  const nodePath = selectedNode.path;

  statusEl.textContent = 'Saving...';
  statusEl.classList.add('visible');

  const command = createCommand(
    `Edit function '${funcName}'`,
    async () => {
      await sendCommand('modify_function', { path: scriptPath, name: funcName, body: newCode });
      const node = nodes.find(n => n.path === nodePath) || selectedNode;
      node.functions[funcIndex].body = newCode;
      node.functions[funcIndex].body_lines = newCode.split('\n').length;
    },
    async () => {
      await sendCommand('modify_function', { path: scriptPath, name: funcName, body: oldBody });
      const node = nodes.find(n => n.path === nodePath) || selectedNode;
      node.functions[funcIndex].body = oldBody;
      node.functions[funcIndex].body_lines = oldBody.split('\n').length;
      if (selectedNode && selectedNode.path === nodePath) openPanel(selectedNode);
    }
  );

  try {
    await undoManager.execute(command);
    textarea.dataset.original = newCode;
    statusEl.textContent = 'Saved!';
    saveBtn.classList.remove('active');
    setTimeout(() => { statusEl.classList.remove('visible'); }, 2000);
  } catch (err) {
    statusEl.textContent = 'Error: ' + err.message;
    console.error('Failed to save:', err);
  }
};

// ---- Inline Editing for Variables/Signals ----
function initInlineEditing() {
  // Handle blur on editable fields - save changes
  document.querySelectorAll('.editable').forEach(el => {
    el.addEventListener('blur', handleInlineEdit);
    el.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        el.blur();
      }
      if (e.key === 'Escape') {
        el.textContent = el.dataset.original || '';
        el.blur();
      }
    });
  });

  // Type combobox triggers
  document.querySelectorAll('.combobox-trigger').forEach(el => {
    el.addEventListener('click', () => openTypeCombobox(el));
  });
}

async function handleInlineEdit(e) {
  const el = e.target;
  const li = el.closest('li');
  if (!li) return;

  const newValue = el.textContent.trim();
  const original = el.dataset.original || '';
  const field = el.dataset.field;

  if (newValue === original) return; // No change

  const isSignal = li.dataset.signalIndex !== undefined;
  const isExport = li.dataset.exported === 'true';
  const index = parseInt(isSignal ? li.dataset.signalIndex : li.dataset.varIndex);
  const nodePath = selectedNode.path;

  try {
    if (isSignal) {
      const sig = selectedNode.signals[index];
      const oldName = typeof sig === 'string' ? sig : sig.name;
      const oldParams = typeof sig === 'object' ? sig.params : '';
      const newSig = {
        name: field === 'name' ? newValue : oldName,
        params: field === 'params' ? newValue : oldParams
      };

      const command = createCommand(
        `Update signal '${oldName}'`,
        async () => {
          await sendCommand('modify_signal', {
            path: nodePath, action: 'update',
            old_name: oldName, name: newSig.name, params: newSig.params
          });
          const node = nodes.find(n => n.path === nodePath) || selectedNode;
          node.signals[index] = { ...newSig };
        },
        async () => {
          await sendCommand('modify_signal', {
            path: nodePath, action: 'update',
            old_name: newSig.name, name: oldName, params: oldParams
          });
          const node = nodes.find(n => n.path === nodePath) || selectedNode;
          node.signals[index] = typeof sig === 'string' ? sig : { name: oldName, params: oldParams };
          if (selectedNode && selectedNode.path === nodePath) openPanel(selectedNode);
        }
      );
      await undoManager.execute(command);
    } else {
      const vars = selectedNode.variables.filter(v => v.exported === isExport);
      const v = vars[index];
      const actualIndex = selectedNode.variables.findIndex(vr => vr.name === v.name);

      if (actualIndex !== -1) {
        const oldVar = { ...selectedNode.variables[actualIndex] };
        const newVar = { ...oldVar };
        if (field === 'name') newVar.name = newValue;
        if (field === 'type') newVar.type = newValue;
        if (field === 'default') newVar.default = newValue;

        const command = createCommand(
          `Update variable '${oldVar.name}'`,
          async () => {
            await sendCommand('modify_variable', {
              path: nodePath, action: 'update',
              old_name: oldVar.name, name: newVar.name,
              type: newVar.type, default: newVar.default, exported: isExport
            });
            const node = nodes.find(n => n.path === nodePath) || selectedNode;
            const ai = node.variables.findIndex(vr => vr.name === oldVar.name);
            if (ai !== -1) node.variables[ai] = { ...newVar };
          },
          async () => {
            await sendCommand('modify_variable', {
              path: nodePath, action: 'update',
              old_name: newVar.name, name: oldVar.name,
              type: oldVar.type, default: oldVar.default, exported: isExport
            });
            const node = nodes.find(n => n.path === nodePath) || selectedNode;
            const ai = node.variables.findIndex(vr => vr.name === newVar.name);
            if (ai !== -1) node.variables[ai] = { ...oldVar };
            if (selectedNode && selectedNode.path === nodePath) openPanel(selectedNode);
          }
        );
        await undoManager.execute(command);
      }
    }

    el.dataset.original = newValue;
  } catch (err) {
    console.error('Failed to update:', err);
    el.textContent = original;
    alert('Failed to save: ' + err.message);
  }
}

// ---- Toggle @onready ----
window.toggleOnready = async function (index, isExport) {
  const vars = selectedNode.variables.filter(v => v.exported === isExport);
  const v = vars[index];
  const actualIndex = selectedNode.variables.findIndex(vr => vr.name === v.name);

  if (actualIndex === -1) return;

  const oldOnready = !!v.onready;
  const nodePath = selectedNode.path;

  const command = createCommand(
    `Toggle @onready on '${v.name}'`,
    async () => {
      await sendCommand('modify_variable', {
        path: nodePath, action: 'update', old_name: v.name,
        name: v.name, type: v.type || '', default: v.default || '',
        exported: isExport, onready: !oldOnready
      });
      const node = nodes.find(n => n.path === nodePath) || selectedNode;
      const ai = node.variables.findIndex(vr => vr.name === v.name);
      if (ai !== -1) node.variables[ai].onready = !oldOnready;
      if (selectedNode && selectedNode.path === nodePath) openPanel(selectedNode);
    },
    async () => {
      await sendCommand('modify_variable', {
        path: nodePath, action: 'update', old_name: v.name,
        name: v.name, type: v.type || '', default: v.default || '',
        exported: isExport, onready: oldOnready
      });
      const node = nodes.find(n => n.path === nodePath) || selectedNode;
      const ai = node.variables.findIndex(vr => vr.name === v.name);
      if (ai !== -1) node.variables[ai].onready = oldOnready;
      if (selectedNode && selectedNode.path === nodePath) openPanel(selectedNode);
    }
  );

  try {
    await undoManager.execute(command);
  } catch (err) {
    console.error('Failed to toggle @onready:', err);
    alert('Failed to update: ' + err.message);
  }
};

// ---- Add New Items ----
window.addNewVariable = async function (isExport) {
  const newVar = { name: 'new_var', type: '', default: '', exported: isExport };
  const nodePath = selectedNode.path;

  const command = createCommand(
    `Add ${isExport ? 'export' : 'variable'} 'new_var'`,
    async () => {
      await sendCommand('modify_variable', {
        path: nodePath, action: 'add',
        name: newVar.name, type: newVar.type, default: newVar.default, exported: isExport
      });
      const node = nodes.find(n => n.path === nodePath) || selectedNode;
      node.variables.push({ ...newVar });
      if (selectedNode && selectedNode.path === nodePath) openPanel(selectedNode);
    },
    async () => {
      await sendCommand('modify_variable', {
        path: nodePath, action: 'delete', old_name: newVar.name
      });
      const node = nodes.find(n => n.path === nodePath) || selectedNode;
      const idx = node.variables.findIndex(v => v.name === newVar.name && v.exported === isExport);
      if (idx !== -1) node.variables.splice(idx, 1);
      if (selectedNode && selectedNode.path === nodePath) openPanel(selectedNode);
    }
  );

  try {
    await undoManager.execute(command);
    setTimeout(() => {
      const list = document.getElementById(isExport ? 'exports-list' : 'vars-list');
      const lastItem = list?.querySelector('li:last-of-type .var-name');
      if (lastItem) {
        lastItem.focus();
        const range = document.createRange();
        range.selectNodeContents(lastItem);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
      }
    }, 50);
  } catch (err) {
    console.error('Failed to add variable:', err);
    alert('Failed to add variable: ' + err.message);
  }
};

window.addNewSignal = async function () {
  const newSig = { name: 'new_signal', params: '' };
  const nodePath = selectedNode.path;

  const command = createCommand(
    `Add signal 'new_signal'`,
    async () => {
      await sendCommand('modify_signal', {
        path: nodePath, action: 'add', name: newSig.name, params: newSig.params
      });
      const node = nodes.find(n => n.path === nodePath) || selectedNode;
      if (!node.signals) node.signals = [];
      node.signals.push({ ...newSig });
      if (selectedNode && selectedNode.path === nodePath) openPanel(selectedNode);
    },
    async () => {
      await sendCommand('modify_signal', {
        path: nodePath, action: 'delete', old_name: newSig.name
      });
      const node = nodes.find(n => n.path === nodePath) || selectedNode;
      const idx = node.signals.findIndex(s => (typeof s === 'string' ? s : s.name) === newSig.name);
      if (idx !== -1) node.signals.splice(idx, 1);
      if (selectedNode && selectedNode.path === nodePath) openPanel(selectedNode);
    }
  );

  try {
    await undoManager.execute(command);
    setTimeout(() => {
      const list = document.getElementById('signals-list');
      const lastItem = list?.querySelector('li:last-of-type .signal-name');
      if (lastItem) {
        lastItem.focus();
        const range = document.createRange();
        range.selectNodeContents(lastItem);
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
      }
    }, 50);
  } catch (err) {
    console.error('Failed to add signal:', err);
    alert('Failed to add signal: ' + err.message);
  }
};

// Section resizing
let resizingList = null;
let resizeStartY = 0;
let resizeStartHeight = 0;

function initSectionResizing() {
  document.querySelectorAll('.section-resize-handle').forEach(handle => {
    // Remove old listeners
    handle.replaceWith(handle.cloneNode(true));
  });

  document.querySelectorAll('.section-resize-handle').forEach(handle => {
    handle.addEventListener('mousedown', (e) => {
      e.preventDefault();
      e.stopPropagation();

      // Find the item-list in this section
      const section = handle.closest('.section');
      resizingList = section?.querySelector('.item-list');
      if (!resizingList) return;

      section.classList.add('resizing');
      resizeStartY = e.clientY;
      resizeStartHeight = resizingList.offsetHeight;

      document.addEventListener('mousemove', onSectionResize);
      document.addEventListener('mouseup', onSectionResizeEnd);
    });
  });
}

function onSectionResize(e) {
  if (!resizingList) return;
  const dy = e.clientY - resizeStartY;
  const newHeight = Math.max(50, Math.min(500, resizeStartHeight + dy));
  resizingList.style.maxHeight = newHeight + 'px';
}

function onSectionResizeEnd() {
  if (resizingList) {
    const section = resizingList.closest('.section');
    section?.classList.remove('resizing');
    resizingList = null;
  }
  document.removeEventListener('mousemove', onSectionResize);
  document.removeEventListener('mouseup', onSectionResizeEnd);
}

// Panel horizontal resizing
let panelResizing = false;
let panelResizeStartX = 0;
let panelStartWidth = 460;

function initPanelResizing() {
  const handle = document.getElementById('panel-resize-handle');
  const panel = document.getElementById('detail-panel');

  handle.addEventListener('mousedown', (e) => {
    e.preventDefault();
    e.stopPropagation();
    panelResizing = true;
    panel.classList.add('resizing');
    panelResizeStartX = e.clientX;
    panelStartWidth = panel.offsetWidth;

    document.addEventListener('mousemove', onPanelResize);
    document.addEventListener('mouseup', onPanelResizeEnd);
  });
}

function onPanelResize(e) {
  if (!panelResizing) return;
  const panel = document.getElementById('detail-panel');
  const dx = panelResizeStartX - e.clientX; // Dragging left = wider
  const newWidth = Math.max(300, Math.min(window.innerWidth * 0.8, panelStartWidth + dx));
  panel.style.width = newWidth + 'px';
  panel.style.right = '0';
}

function onPanelResizeEnd() {
  panelResizing = false;
  const panel = document.getElementById('detail-panel');
  panel.classList.remove('resizing');
  document.removeEventListener('mousemove', onPanelResize);
  document.removeEventListener('mouseup', onPanelResizeEnd);
}

// Function to expand and highlight a specific line in a function viewer
export function expandAndHighlightFunction(funcName, targetLine, nodeData) {
  const node = nodeData || selectedNode;

  // Find the function index
  const funcIndex = node.functions.findIndex(f => f.name === funcName);
  if (funcIndex === -1) return;

  // Get the function viewer element
  const viewer = document.getElementById(`func-viewer-${funcIndex}`);
  if (!viewer) return;

  // Check if already expanded
  const isExpanded = viewer.style.display !== 'none';

  if (!isExpanded) {
    // Need to expand - call toggleFunc
    window.toggleFunc(funcIndex);
  }

  // Wait for expansion, then highlight
  setTimeout(() => {
    highlightLineInViewer(viewer, funcName, targetLine, node);
    // Scroll the viewer into view
    viewer.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }, isExpanded ? 100 : 300);
}

function highlightLineInViewer(viewer, funcName, targetLine, nodeData) {
  // Find the function to get its start line
  const node = nodeData || selectedNode;
  const func = node.functions.find(f => f.name === funcName);
  if (!func) return;

  const funcStartLine = func.line || 1;
  const relativeLineIndex = targetLine - funcStartLine;

  // Find the highlight overlay within the viewer
  const highlightDiv = viewer.querySelector('.code-editor-highlight');
  if (!highlightDiv) return;

  // Clear all previous highlights
  document.querySelectorAll('.code-line-highlight').forEach(el => {
    el.classList.remove('code-line-highlight');
  });

  // Get all lines and highlight the target
  const lines = highlightDiv.querySelectorAll('.code-line');

  if (relativeLineIndex >= 0 && relativeLineIndex < lines.length) {
    const targetLineEl = lines[relativeLineIndex];
    targetLineEl.classList.add('code-line-highlight');

    // Scroll the line into view within the code editor
    setTimeout(() => {
      targetLineEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }, 50);
  }
}

// ============================================================================
// SCENE NODE PROPERTIES PANEL
// ============================================================================

export async function openSceneNodePanel(scenePath, node) {
  currentPanelMode = 'sceneNode';
  setSelectedSceneNode(node);

  // Show loading state
  document.getElementById('panel-title').textContent = node.name;
  document.getElementById('panel-path').textContent = `${node.type} • ${node.path}`;
  document.getElementById('panel-body').innerHTML = '<div class="loading-state">Loading properties...</div>';
  detailPanel.classList.add('open');

  try {
    // Fetch properties from Godot
    const result = await sendCommand('get_scene_node_properties', {
      scene_path: scenePath,
      node_path: node.path
    });

    if (result.ok) {
      setSceneNodeProperties(result);
      renderSceneNodePanel(result, scenePath, node);
    } else {
      document.getElementById('panel-body').innerHTML = `<div class="error-state">Failed to load properties: ${result.error}</div>`;
    }
  } catch (err) {
    console.error('Failed to fetch node properties:', err);
    document.getElementById('panel-body').innerHTML = `<div class="error-state">Error: ${err.message}</div>`;
  }
}

export function closeSceneNodePanel() {
  if (currentPanelMode === 'sceneNode') {
    setSelectedSceneNode(null);
    setSceneNodeProperties(null);
    detailPanel.classList.remove('open');
    draw();
  }
}

function renderSceneNodePanel(data, scenePath, node) {
  document.getElementById('panel-title').textContent = data.node_name;
  document.getElementById('panel-path').textContent = `${data.node_type} • ${data.node_path}`;

  let html = '';

  // Meta badges
  html += `<div class="meta-row">`;
  html += `<div class="meta-badge"><span>${data.node_type}</span></div>`;
  html += `<div class="meta-badge">${data.property_count} <span>properties</span></div>`;
  if (node.script) {
    html += `<div class="meta-badge script-badge" onclick="jumpToScript('${esc(node.script)}')">📜 <span>${node.script.split('/').pop()}</span></div>`;
  }
  html += `</div>`;

  // Render categories
  const categories = data.categories || {};
  const categoryOrder = data.inheritance_chain || Object.keys(categories);

  for (const category of categoryOrder) {
    const props = categories[category];
    if (!props || props.length === 0) continue;

    html += `<div class="section property-section" data-category="${esc(category)}">`;
    html += `<div class="section-header clickable" onclick="togglePropertySection(this)">`;
    html += `<span>${category}</span>`;
    html += `<span class="section-count">${props.length}</span>`;
    html += `</div>`;
    html += `<div class="property-list">`;

    for (const prop of props) {
      html += renderPropertyRow(prop, scenePath, data.node_path);
    }

    html += `</div></div>`;
  }

  document.getElementById('panel-body').innerHTML = html;
  initPropertyEditing(scenePath, data.node_path);
}

// Convert snake_case to Title Case for display
function formatPropertyName(name) {
  return name
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase());
}

function renderPropertyRow(prop, scenePath, nodePath) {
  const { name, type, type_name, value, hint, hint_string } = prop;
  const displayName = formatPropertyName(name);

  let html = `<div class="property-row" data-prop="${esc(name)}" data-type="${type}">`;
  html += `<label class="property-name" title="${esc(name)}">${esc(displayName)}</label>`;
  html += `<div class="property-value">`;

  // Render appropriate control based on type
  switch (type) {
    case 1: // TYPE_BOOL
      const boolChecked = value === true ? 'checked' : '';
      html += `<label class="toggle-switch">
        <input type="checkbox" ${boolChecked} data-prop="${esc(name)}" data-type="${type}">
        <span class="toggle-slider"></span>
      </label>`;
      break;

    case 2: // TYPE_INT
      if (hint === 2 && hint_string) { // PROPERTY_HINT_ENUM
        html += renderEnumSelect(name, type, value, hint_string);
      } else if (hint === 1 && hint_string) { // PROPERTY_HINT_RANGE
        html += renderRangeSlider(name, type, value, hint_string, true);
      } else {
        html += `<input type="number" class="property-input" value="${value ?? 0}" step="1" data-prop="${esc(name)}" data-type="${type}">`;
      }
      break;

    case 3: // TYPE_FLOAT
      if (hint === 1 && hint_string) { // PROPERTY_HINT_RANGE
        html += renderRangeSlider(name, type, value, hint_string, false);
      } else {
        html += `<input type="number" class="property-input" value="${value ?? 0}" step="0.01" data-prop="${esc(name)}" data-type="${type}">`;
      }
      break;

    case 4: // TYPE_STRING
      html += `<input type="text" class="property-input" value="${esc(value || '')}" data-prop="${esc(name)}" data-type="${type}">`;
      break;

    case 5: // TYPE_VECTOR2
      html += renderVector2Input(name, type, value);
      break;

    case 6: // TYPE_VECTOR2I
      html += renderVector2Input(name, type, value, true);
      break;

    case 9: // TYPE_VECTOR3
      html += renderVector3Input(name, type, value);
      break;

    case 10: // TYPE_VECTOR3I
      html += renderVector3Input(name, type, value, true);
      break;

    case 20: // TYPE_COLOR
      html += renderColorInput(name, type, value);
      break;

    case 24: // TYPE_OBJECT (Resource)
      if (value && value.type === 'Resource') {
        html += `<span class="resource-path">${esc(value.path || 'null')}</span>`;
      } else {
        html += `<span class="resource-path">null</span>`;
      }
      break;

    default:
      // Display value as text for unsupported types
      const displayValue = typeof value === 'object' ? JSON.stringify(value) : String(value ?? 'null');
      html += `<span class="property-readonly">${esc(displayValue.substring(0, 50))}${displayValue.length > 50 ? '...' : ''}</span>`;
  }

  html += `</div></div>`;
  return html;
}

function renderEnumSelect(name, type, value, hintString) {
  const options = hintString.split(',').map(opt => {
    const parts = opt.split(':');
    return { value: parts.length > 1 ? parseInt(parts[0]) : opt.trim(), label: parts.length > 1 ? parts[1].trim() : opt.trim() };
  });

  let html = `<select class="property-select" data-prop="${esc(name)}" data-type="${type}">`;
  for (const opt of options) {
    const selected = opt.value === value ? 'selected' : '';
    html += `<option value="${opt.value}" ${selected}>${esc(opt.label)}</option>`;
  }
  html += `</select>`;
  return html;
}

function renderRangeSlider(name, type, value, hintString, isInt) {
  const parts = hintString.split(',');
  const min = parseFloat(parts[0]) || 0;
  const max = parseFloat(parts[1]) || 100;
  const step = parts[2] ? parseFloat(parts[2]) : (isInt ? 1 : 0.01);

  return `<div class="range-input-group">
    <input type="range" class="property-range" value="${value ?? min}" min="${min}" max="${max}" step="${step}" data-prop="${esc(name)}" data-type="${type}">
    <input type="number" class="property-input range-number" value="${value ?? min}" min="${min}" max="${max}" step="${step}" data-prop="${esc(name)}" data-type="${type}">
  </div>`;
}

function renderVector2Input(name, type, value, isInt = false) {
  const x = value?.x ?? 0;
  const y = value?.y ?? 0;
  const step = isInt ? '1' : '0.01';

  return `<div class="vector-input-group" data-prop="${esc(name)}" data-type="${type}">
    <label>x</label><input type="number" class="property-input vec-x" value="${x}" step="${step}" data-component="x">
    <label>y</label><input type="number" class="property-input vec-y" value="${y}" step="${step}" data-component="y">
  </div>`;
}

function renderVector3Input(name, type, value, isInt = false) {
  const x = value?.x ?? 0;
  const y = value?.y ?? 0;
  const z = value?.z ?? 0;
  const step = isInt ? '1' : '0.01';

  return `<div class="vector-input-group vec3" data-prop="${esc(name)}" data-type="${type}">
    <label>x</label><input type="number" class="property-input vec-x" value="${x}" step="${step}" data-component="x">
    <label>y</label><input type="number" class="property-input vec-y" value="${y}" step="${step}" data-component="y">
    <label>z</label><input type="number" class="property-input vec-z" value="${z}" step="${step}" data-component="z">
  </div>`;
}

function renderColorInput(name, type, value) {
  const r = Math.round((value?.r ?? 1) * 255);
  const g = Math.round((value?.g ?? 1) * 255);
  const b = Math.round((value?.b ?? 1) * 255);
  const a = value?.a ?? 1;
  const hex = `#${r.toString(16).padStart(2, '0')}${g.toString(16).padStart(2, '0')}${b.toString(16).padStart(2, '0')}`;

  return `<div class="color-input-group" data-prop="${esc(name)}" data-type="${type}">
    <input type="color" class="property-color" value="${hex}" data-prop="${esc(name)}">
    <input type="number" class="property-input color-alpha" value="${a}" min="0" max="1" step="0.01" placeholder="α" data-component="a">
  </div>`;
}

function initPropertyEditing(scenePath, nodePath) {
  // Boolean toggles
  document.querySelectorAll('.property-row input[type="checkbox"]').forEach(el => {
    el.addEventListener('change', () => {
      const propName = el.dataset.prop;
      const oldValue = !el.checked; // Before toggle
      saveSceneNodeProperty(scenePath, nodePath, propName, el.checked, parseInt(el.dataset.type), oldValue);
    });
  });

  // Number and text inputs — capture old value on focus
  document.querySelectorAll('.property-row input.property-input:not(.vec-x):not(.vec-y):not(.vec-z):not(.color-alpha):not(.range-number)').forEach(el => {
    el.addEventListener('focus', () => { el.dataset.prev = el.value; });
    el.addEventListener('change', () => {
      const propName = el.dataset.prop;
      const type = parseInt(el.dataset.type);
      let value = el.value;
      let oldValue = el.dataset.prev || '';
      if (type === 2 || type === 3) { value = parseFloat(value); oldValue = parseFloat(oldValue); }
      saveSceneNodeProperty(scenePath, nodePath, propName, value, type, oldValue);
      el.dataset.prev = el.value;
    });
  });

  // Select dropdowns
  document.querySelectorAll('.property-row select.property-select').forEach(el => {
    el.addEventListener('focus', () => { el.dataset.prev = el.value; });
    el.addEventListener('change', () => {
      const propName = el.dataset.prop;
      const type = parseInt(el.dataset.type);
      const oldValue = parseInt(el.dataset.prev || el.value);
      saveSceneNodeProperty(scenePath, nodePath, propName, parseInt(el.value), type, oldValue);
      el.dataset.prev = el.value;
    });
  });

  // Range sliders (sync with number input)
  document.querySelectorAll('.range-input-group').forEach(group => {
    const range = group.querySelector('input[type="range"]');
    const number = group.querySelector('input[type="number"]');
    let prevRangeVal = parseFloat(range.value);

    range.addEventListener('input', () => { number.value = range.value; });
    range.addEventListener('mousedown', () => { prevRangeVal = parseFloat(range.value); });
    range.addEventListener('change', () => {
      const propName = range.dataset.prop;
      const type = parseInt(range.dataset.type);
      saveSceneNodeProperty(scenePath, nodePath, propName, parseFloat(range.value), type, prevRangeVal);
      prevRangeVal = parseFloat(range.value);
    });
    number.addEventListener('focus', () => { number.dataset.prev = number.value; });
    number.addEventListener('change', () => {
      range.value = number.value;
      const propName = number.dataset.prop;
      const type = parseInt(number.dataset.type);
      const oldValue = parseFloat(number.dataset.prev || number.value);
      saveSceneNodeProperty(scenePath, nodePath, propName, parseFloat(number.value), type, oldValue);
      number.dataset.prev = number.value;
    });
  });

  // Vector inputs — capture old vector on focus
  document.querySelectorAll('.vector-input-group').forEach(group => {
    const propName = group.dataset.prop;
    const type = parseInt(group.dataset.type);
    const inputs = group.querySelectorAll('input');
    let prevVec = null;

    const getVec = () => {
      const x = parseFloat(group.querySelector('.vec-x').value);
      const y = parseFloat(group.querySelector('.vec-y').value);
      const zInput = group.querySelector('.vec-z');
      return zInput ? { x, y, z: parseFloat(zInput.value) } : { x, y };
    };

    inputs.forEach(input => {
      input.addEventListener('focus', () => { prevVec = getVec(); });
      input.addEventListener('change', () => {
        const value = getVec();
        saveSceneNodeProperty(scenePath, nodePath, propName, value, type, prevVec);
        prevVec = { ...value };
      });
    });
  });

  // Color inputs — capture old color on focus
  document.querySelectorAll('.color-input-group').forEach(group => {
    const propName = group.dataset.prop;
    const type = parseInt(group.dataset.type);
    const colorInput = group.querySelector('input[type="color"]');
    const alphaInput = group.querySelector('.color-alpha');
    let prevColor = null;

    const getColor = () => {
      const hex = colorInput.value;
      return {
        r: parseInt(hex.substr(1, 2), 16) / 255,
        g: parseInt(hex.substr(3, 2), 16) / 255,
        b: parseInt(hex.substr(5, 2), 16) / 255,
        a: parseFloat(alphaInput.value)
      };
    };

    colorInput.addEventListener('focus', () => { prevColor = getColor(); });
    alphaInput.addEventListener('focus', () => { prevColor = getColor(); });
    const saveColor = () => {
      const value = getColor();
      saveSceneNodeProperty(scenePath, nodePath, propName, value, type, prevColor);
      prevColor = { ...value };
    };

    colorInput.addEventListener('change', saveColor);
    alphaInput.addEventListener('change', saveColor);
  });
}

async function saveSceneNodeProperty(scenePath, nodePath, propName, value, valueType, oldValue) {
  const command = createCommand(
    `Set '${propName}'`,
    async () => {
      const result = await sendCommand('set_scene_node_property', {
        scene_path: scenePath, node_path: nodePath,
        property_name: propName, value: value, value_type: valueType
      });
      if (!result.ok) throw new Error(result.error || 'Unknown error');
    },
    async () => {
      if (oldValue === undefined) return; // Can't undo without old value
      const result = await sendCommand('set_scene_node_property', {
        scene_path: scenePath, node_path: nodePath,
        property_name: propName, value: oldValue, value_type: valueType
      });
      if (!result.ok) throw new Error(result.error || 'Unknown error');
      // Re-open the panel to reflect restored value
      if (selectedSceneNode) {
        await openSceneNodePanel(scenePath, selectedSceneNode);
      }
    }
  );

  try {
    await undoManager.execute(command);
  } catch (err) {
    console.error('Failed to save property:', err);
    alert('Failed to save: ' + err.message);
  }
}

// Toggle property section visibility
window.togglePropertySection = function(header) {
  const section = header.closest('.property-section');
  section.classList.toggle('collapsed');
};

// Jump to script in scripts view
window.jumpToScript = function(scriptPath) {
  // Switch to scripts view and select the script
  window.switchView('scripts');
  // Find and select the node
  const scriptNode = nodes.find(n => n.path === scriptPath);
  if (scriptNode) {
    setTimeout(() => openPanel(scriptNode), 100);
  }
};

// Jump to scene in scenes view
window.jumpToScene = function(scenePath) {
  // Switch to scenes view and expand the scene
  closePanel();
  window.switchView('scenes');
  // Trigger scene expansion after view switch
  setTimeout(() => {
    window.expandSceneFromPanel && window.expandSceneFromPanel(scenePath);
  }, 100);
};
