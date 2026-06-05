/**
 * TunedPC Controller Overclocker — scripts décryptés depuis TunedPC-Setup (Apply / Detect).
 * Chemins : resources/scripts/*.ps1, resources/hidusbf
 */
const fs = require('fs');
const path = require('path');
const { spawn, execSync } = require('child_process');
const { app } = require('electron');
const { getHidusbfDriverDir, getScriptsDir, resolveScriptPath } = require('./paths');

const VALID_RATES = [125, 250, 500, 1000, 2000, 4000, 8000];
const ADMIN_REQUIRED_MSG = "Lance l'application en administrateur pour modifier HIDUSBF.";

function isProcessElevated() {
  if (process.platform !== 'win32') return false;
  try {
    const out = execSync(
      'powershell.exe -NoProfile -Command "(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"',
      { encoding: 'utf8', windowsHide: true, timeout: 8000 }
    );
    return String(out).trim().toLowerCase() === 'true';
  } catch {
    return false;
  }
}

function mapOcUserError(message) {
  const msg = String(message || '');
  if (!isProcessElevated() && /registry|registre|access is denied|accès refusé|unauthorized|administrateur|élévation|elevated|denied/i.test(msg)) {
    return ADMIN_REQUIRED_MSG;
  }
  return msg;
}

function getOcStateFile() {
  return path.join(app.getPath('userData'), 'controller-oc-state.json');
}

function readOcDeviceIds() {
  try {
    const raw = fs.readFileSync(getOcStateFile(), 'utf8');
    const data = JSON.parse(raw);
    return Array.isArray(data.overclockedDeviceIds) ? data.overclockedDeviceIds : [];
  } catch (err) {
    if (err && err.code === 'ENOENT') return [];
    return [];
  }
}

function writeOcDeviceIds(ids) {
  try {
    fs.mkdirSync(path.dirname(getOcStateFile()), { recursive: true });
    fs.writeFileSync(getOcStateFile(), JSON.stringify({ overclockedDeviceIds: ids }, null, 2), 'utf8');
    return true;
  } catch {
    return false;
  }
}

function isValidRate(rate) {
  return VALID_RATES.includes(Number(rate));
}

function isValidInstanceId(id) {
  if (!id || typeof id !== 'string') return false;
  if (id.length > 512) return false;
  return /^[A-Za-z0-9\\_&#]+$/.test(id);
}

function runPowerShellScript(scriptName, envVars = {}) {
  const scriptPath = resolveScriptPath(scriptName);
  console.log(`[controller-oc] run ${scriptName} script=${scriptPath}`);

  if (!fs.existsSync(scriptPath)) {
    return Promise.resolve({
      success: false,
      output: [],
      errors: [`Script introuvable: ${scriptPath}`],
      exitCode: -1
    });
  }

  const psArgs = [
    '-ExecutionPolicy', 'Bypass',
    '-NoProfile',
    '-NonInteractive',
    '-File', scriptPath
  ];

  return new Promise((resolve) => {
    const child = spawn('powershell.exe', psArgs, {
      cwd: getScriptsDir(),
      env: { ...process.env, ...envVars },
      windowsHide: true,
      shell: false
    });

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (d) => { stdout += d.toString('utf8'); });
    child.stderr.on('data', (d) => { stderr += d.toString('utf8'); });

    child.on('close', (code) => {
      const output = stdout.split(/\r?\n/).filter((l) => l.length > 0);
      const errors = stderr.split(/\r?\n/).filter((l) => l.length > 0);
      resolve({
        success: code === 0,
        output,
        errors,
        exitCode: code ?? -1
      });
    });

    child.on('error', (err) => {
      resolve({
        success: false,
        output: [],
        errors: [String(err.message || err)],
        exitCode: -1
      });
    });
  });
}

function parseLastJsonLine(output) {
  for (let i = output.length - 1; i >= 0; i--) {
    const t = output[i].trim();
    if (t.startsWith('{') && t.endsWith('}')) {
      try {
        return JSON.parse(t);
      } catch {
        /* continue */
      }
    }
  }
  return null;
}

function parseSqFail(output) {
  const fail = output.find((line) => line.includes('[SQ_CHECK_FAIL:'));
  if (!fail) return null;
  return fail.replace(/.*\[SQ_CHECK_FAIL:[^:]*:?/, '').replace(/\].*/, '').trim();
}

function parseSqWarnings(output) {
  return output
    .filter((line) => line.includes('[SQ_CHECK_WARN:'))
    .map((line) => {
      const m = line.match(/\[SQ_CHECK_WARN:[^:]*:?(.*)\]/);
      return m ? m[1].trim() : '';
    })
    .filter(Boolean);
}

function mapPrerequisitesForUi(raw) {
  const p = raw && typeof raw === 'object' ? raw : {};
  const ok = p.hidusbfDriverAvailable === true;
  return {
    ok,
    available: ok,
    message: ok ? 'HIDUSBF driver bundle OK' : 'HIDUSBF driver bundle not found',
    driverPath: getHidusbfDriverDir(),
    hidusbfServiceInstalled: p.hidusbfServiceInstalled === true,
    memoryIntegrityEnabled: p.memoryIntegrityEnabled === true
  };
}

function findDeviceInScan(scan, instanceId) {
  if (!scan || !instanceId) return null;
  const rawList = Array.isArray(scan.devices) ? scan.devices : [];
  const raw = rawList.find((d) => d.instanceId === instanceId);
  if (raw) return raw;
  const mapped = (scan.controllers || []).find((d) => d.instanceId === instanceId);
  if (!mapped) return null;
  return {
    instanceId: mapped.instanceId,
    currentRateHz: mapped.currentPollingRate,
    hasFilter: mapped.hasFilter,
    type: String(mapped.type || 'other').toLowerCase()
  };
}

function boostedRateThreshold(device) {
  const type = String(device?.type || 'other').toLowerCase();
  return type === 'ps5' ? 8000 : 1000;
}

/** Remove confirmé seulement si plus à 1000/8000 Hz et filtre retiré ou polling ≤125. */
function isRemoveConfirmed(device) {
  if (!device) return false;
  const rate = Number(device.currentRateHz ?? device.currentPollingRate) || 125;
  const hasFilter = device.hasFilter === true;
  const threshold = boostedRateThreshold(device);
  if (rate >= threshold) return false;
  if (rate <= 125) return true;
  if (!hasFilter) return true;
  return false;
}

function mapDeviceForUi(d) {
  const typeRaw = String(d.type || 'other');
  const typeMap = {
    ps5: 'PS5',
    ps4: 'PS4',
    xbox: 'Xbox',
    nintendo: 'Generic',
    mouse: 'Generic',
    other: 'Generic'
  };
  const type = typeMap[typeRaw] || 'Generic';
  const max = type === 'PS5' ? 8000 : 1000;
  const cur = Number(d.currentRateHz) || 125;
  const hasFilter = d.hasFilter === true;
  const inst = d.instanceId;
  const parent = d.usbParentId || inst;

  return {
    id: parent || inst,
    instanceId: inst,
    hidusbfTargetId: parent,
    parentInstanceId: parent,
    name: d.friendlyName || 'Controller',
    type,
    currentPollingRate: cur,
    maxPollingRate: max,
    hasFilter,
    hidusbfTargetReliable: Boolean(parent),
    canBoost: !hasFilter && type !== 'mouse',
    boostButton: hasFilter ? 'remove' : (max >= 8000 ? '8000' : '1000'),
    present: true,
    compatible: type !== 'mouse'
  };
}

async function enumerate() {
  try {
    console.log(`[controller-oc] ENUMERATE_START elevated=${isProcessElevated()}`);
    const driverDir = getHidusbfDriverDir();
    const envVars = {};
    if (fs.existsSync(driverDir)) {
      envVars.HIDUSBF_DRIVER_PATH = driverDir;
    }

    const result = await runPowerShellScript('Detect-USBDevices.ps1', envVars);
    const parsed = parseLastJsonLine(result.output);

    if (parsed && Array.isArray(parsed.devices)) {
      const controllers = parsed.devices.map(mapDeviceForUi);
      const hidusbf = mapPrerequisitesForUi(parsed.prerequisites);
      const overclockedIds = readOcDeviceIds();
      const missingFilters = overclockedIds.filter((id) => {
        const device = parsed.devices.find((d) => d.instanceId === id);
        return !device || !device.hasFilter;
      });

      return {
        success: true,
        devices: parsed.devices,
        prerequisites: parsed.prerequisites ?? {},
        missingFilters,
        controllers,
        hidusbf,
        isElevated: isProcessElevated(),
        ok: true,
        status: 'success',
        message: `${controllers.length} manette(s) détectée(s)`,
        data: { controllers, hidusbf }
      };
    }

    if (!result.success) {
      const fail = parseSqFail(result.output);
      return {
        success: false,
        error: fail || result.errors.join(' | ') || `Detection exited with code ${result.exitCode}`,
        devices: [],
        prerequisites: mapPrerequisitesForUi({}),
        controllers: [],
        hidusbf: mapPrerequisitesForUi({})
      };
    }

    return {
      success: false,
      error: 'Detection script did not produce valid JSON output',
      devices: [],
      prerequisites: mapPrerequisitesForUi({}),
      controllers: [],
      hidusbf: mapPrerequisitesForUi({})
    };
  } catch (err) {
    return {
      success: false,
      error: String(err.message || err),
      devices: [],
      prerequisites: mapPrerequisitesForUi({}),
      controllers: [],
      hidusbf: mapPrerequisitesForUi({})
    };
  }
}

async function applyOverclock(instanceId, usbParentId, rateHz) {
  try {
    if (!isProcessElevated()) {
      return { success: false, error: ADMIN_REQUIRED_MSG, ok: false, message: ADMIN_REQUIRED_MSG };
    }
    if (!isValidInstanceId(instanceId)) {
      return { success: false, error: 'Invalid device instance ID.', ok: false, message: 'Invalid device instance ID.' };
    }
    if (!isValidInstanceId(usbParentId)) {
      return { success: false, error: 'Invalid USB parent device ID.', ok: false, message: 'Invalid USB parent device ID.' };
    }
    if (!isValidRate(rateHz)) {
      const msg = `Invalid polling rate: ${rateHz}. Must be 125, 250, 500, 1000, 2000, 4000, or 8000.`;
      return { success: false, error: msg, ok: false, message: msg };
    }

    const envVars = {
      CONTROLLER_OC_INSTANCE_ID: instanceId,
      CONTROLLER_OC_USB_PARENT_ID: usbParentId,
      CONTROLLER_OC_RATE_HZ: String(rateHz),
      CONTROLLER_OC_DRIVER_PATH: getHidusbfDriverDir(),
      CONTROLLER_OC_UNINSTALL: '0'
    };

    const result = await runPowerShellScript('Apply-ControllerOC.ps1', envVars);
    if (!result.success) {
      const errorMsg = mapOcUserError(parseSqFail(result.output)
        || result.errors.join(' | ')
        || `Script exited with code ${result.exitCode}`);
      return { success: false, error: errorMsg, ok: false, message: errorMsg };
    }

    const failMsg = mapOcUserError(parseSqFail(result.output));
    if (failMsg) {
      return { success: false, error: failMsg, ok: false, message: failMsg };
    }

    const warnings = parseSqWarnings(result.output);
    const ids = readOcDeviceIds();
    if (!ids.includes(instanceId)) ids.push(instanceId);
    if (!writeOcDeviceIds(ids)) {
      warnings.push('Boost applied, but state tracking could not be saved.');
    }

    return {
      success: true,
      ok: true,
      status: 'success',
      message: 'Boost appliqué',
      ...(warnings.length ? { warnings } : {})
    };
  } catch (err) {
    const msg = mapOcUserError(err.message || err);
    return { success: false, error: msg, ok: false, message: msg };
  }
}

const REMOVE_NOT_CONFIRMED_MSG =
  'Remove Boost non confirmé, débranche/rebranche la manette puis Refresh';

async function removeOverclock(instanceId, usbParentId) {
  try {
    if (!isProcessElevated()) {
      return { success: false, error: ADMIN_REQUIRED_MSG, ok: false, message: ADMIN_REQUIRED_MSG };
    }
    if (!isValidInstanceId(instanceId)) {
      return { success: false, error: 'Invalid device instance ID.', ok: false, message: 'Invalid device instance ID.' };
    }
    if (!isValidInstanceId(usbParentId)) {
      return { success: false, error: 'Invalid USB parent device ID.', ok: false, message: 'Invalid USB parent device ID.' };
    }

    console.log(`[controller-oc] REMOVE_START instanceId=${instanceId} usbParentId=${usbParentId}`);

    const envVars = {
      CONTROLLER_OC_INSTANCE_ID: instanceId,
      CONTROLLER_OC_USB_PARENT_ID: usbParentId,
      CONTROLLER_OC_DRIVER_PATH: getHidusbfDriverDir(),
      CONTROLLER_OC_UNINSTALL: '1'
    };

    const result = await runPowerShellScript('Apply-ControllerOC.ps1', envVars);
    console.log(`[controller-oc] REMOVE_SCRIPT_EXIT_CODE=${result.exitCode}`);

    if (!result.success) {
      const errorMsg = mapOcUserError(parseSqFail(result.output)
        || result.errors.join(' | ')
        || `Script exited with code ${result.exitCode}`);
      return { success: false, error: errorMsg, ok: false, message: errorMsg };
    }

    const failMsg = mapOcUserError(parseSqFail(result.output));
    if (failMsg) {
      return { success: false, error: failMsg, ok: false, message: failMsg };
    }

    const warnings = parseSqWarnings(result.output);
    const scan = await enumerate();
    console.log(`[controller-oc] REMOVE_DETECT_AFTER success=${scan.success} devices=${(scan.devices || []).length}`);

    const device = findDeviceInScan(scan, instanceId);
    const verifiedRate = Number(device?.currentRateHz ?? device?.currentPollingRate) || 0;
    const confirmed = isRemoveConfirmed(device);
    console.log(`[controller-oc] REMOVE_VERIFIED_RATE=${verifiedRate} hasFilter=${device?.hasFilter === true}`);
    console.log(`[controller-oc] REMOVE_CONFIRMED=${confirmed}`);

    const scanPayload = {
      devices: scan.devices,
      controllers: scan.controllers,
      prerequisites: scan.prerequisites,
      hidusbf: scan.hidusbf,
      data: scan.data
    };

    if (!confirmed) {
      return {
        success: false,
        ok: false,
        status: 'error',
        error: REMOVE_NOT_CONFIRMED_MSG,
        message: REMOVE_NOT_CONFIRMED_MSG,
        verifiedRateHz: verifiedRate,
        ...(warnings.length ? { warnings } : {}),
        ...scanPayload
      };
    }

    const ids = readOcDeviceIds().filter((id) => id !== instanceId);
    if (!writeOcDeviceIds(ids)) {
      warnings.push('Overclock removed, but state tracking could not be saved.');
    }

    return {
      success: true,
      ok: true,
      status: 'success',
      message: 'Boost retiré',
      verifiedRateHz: verifiedRate,
      ...(warnings.length ? { warnings } : {}),
      ...scanPayload
    };
  } catch (err) {
    const msg = mapOcUserError(err.message || err);
    return { success: false, error: msg, ok: false, message: msg };
  }
}

function registerControllerOcHandlers(ipcMain) {
  ipcMain.handle('controllerOc:isElevated', () => isProcessElevated());
  ipcMain.handle('controllerOc:enumerate', () => enumerate());
  ipcMain.handle('controllerOc:applyOverclock', (_e, instanceId, usbParentId, rateHz) =>
    applyOverclock(instanceId, usbParentId, rateHz));
  ipcMain.handle('controllerOc:removeOverclock', (_e, instanceId, usbParentId) =>
    removeOverclock(instanceId, usbParentId));
}

module.exports = {
  enumerate,
  applyOverclock,
  removeOverclock,
  isProcessElevated,
  registerControllerOcHandlers
};
