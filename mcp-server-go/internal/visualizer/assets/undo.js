/**
 * Undo/Redo system using the Command pattern.
 * Each undoable action is wrapped in a command object with execute() and undo().
 */

const MAX_HISTORY = 50;

class UndoManager {
  constructor() {
    this.history = [];
    this.cursor = -1;
    this.locked = false;
  }

  async execute(command) {
    if (this.locked) return;
    this.locked = true;
    try {
      await command.execute();
      // Clear redo entries
      this.history.length = this.cursor + 1;
      this.history.push(command);
      if (this.history.length > MAX_HISTORY) {
        this.history.shift();
      } else {
        this.cursor++;
      }
    } catch (err) {
      showToast(`Failed: ${command.description}`, 'error');
      this.locked = false;
      throw err;
    }
    this.locked = false;
  }

  async undo() {
    if (this.locked || this.cursor < 0) return;
    this.locked = true;
    const command = this.history[this.cursor];
    try {
      await command.undo();
      this.cursor--;
      showToast(`Undo: ${command.description}`, 'undo');
    } catch (err) {
      showToast(`Undo failed: ${command.description}`, 'error');
    }
    this.locked = false;
  }

  async redo() {
    if (this.locked || this.cursor >= this.history.length - 1) return;
    this.locked = true;
    const command = this.history[this.cursor + 1];
    try {
      await command.execute();
      this.cursor++;
      showToast(`Redo: ${command.description}`, 'redo');
    } catch (err) {
      showToast(`Redo failed: ${command.description}`, 'error');
    }
    this.locked = false;
  }

  canUndo() { return this.cursor >= 0 && !this.locked; }
  canRedo() { return this.cursor < this.history.length - 1 && !this.locked; }

  clear() {
    this.history = [];
    this.cursor = -1;
  }
}

export const undoManager = new UndoManager();

export function createCommand(description, executeFn, undoFn) {
  return { description, execute: executeFn, undo: undoFn };
}

// Toast notification
let toastTimeout = null;

function showToast(message, type = 'action') {
  let toast = document.getElementById('undo-toast');
  if (!toast) {
    toast = document.createElement('div');
    toast.id = 'undo-toast';
    toast.className = 'undo-toast';
    document.body.appendChild(toast);
  }

  toast.textContent = message;
  toast.className = `undo-toast visible ${type}`;

  clearTimeout(toastTimeout);
  toastTimeout = setTimeout(() => {
    toast.classList.remove('visible');
  }, 2500);
}

export { showToast };
