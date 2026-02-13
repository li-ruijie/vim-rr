vim9script

if exists("g:did_vimr_rstudio")
    finish
endif
g:did_vimr_rstudio = 1

var ps_script_path = ''

def g:StartRStudio()
    if string(g:SendCmdToR) != "function('g:SendCmdToR_fake')"
        return
    endif

    g:SendCmdToR = function('g:SendCmdToR_NotYet')

    if has("win32")
        g:SetRHome()
    endif
    g:rplugin.jobs["RStudio"] = g:StartJob([g:RStudio_cmd], {
        'err_cb':  'g:ROnJobStderr',
        'exit_cb': 'g:ROnJobExit',
        'stoponexit': ''})
    if has("win32")
        g:UnsetRHome()
        # Vim's job_start() passes SW_HIDE via STARTUPINFO on Windows,
        # which Electron (RStudio) respects.  Force the window visible.
        var pid = job_info(g:rplugin.jobs['RStudio']).process
        EnsureWindowVisible(pid)
    endif

    g:WaitVimcomStart()
enddef

# Poll for RStudio's Electron window and call ShowWindow(hwnd, SW_RESTORE).
# Electron apps are multi-process and don't set MainWindowHandle — we must
# use EnumWindows + GetWindowThreadProcessId to find Chrome_WidgetWin_1
# windows across all rstudio.exe processes.  SW_RESTORE (9) is required
# because SW_SHOW (5) has no effect on windows started with SW_HIDE.
# Only windows with a non-empty title are targeted (Electron helper windows
# have empty titles).  Every titled Chrome_WidgetWin_1 in the process tree
# gets ShowWindow if not already visible, with IsWindowVisible confirmation.
# Once any window is visible, a 5-second guard phase re-enumerates all
# windows and re-shows any that Electron's startup sequence hides again.
# A single PowerShell invocation loops internally (100ms x 200 = 20s).
def EnsureWindowVisible(pid: number)
    if ps_script_path == ''
        ps_script_path = g:rplugin.tmpdir .. '/show_window.ps1'
        var code = [
            'param([int]$RootPid)',
            'Add-Type @"',
            'using System;',
            'using System.Runtime.InteropServices;',
            'using System.Text;',
            'public class RStudioWin {',
            '    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);',
            '    [DllImport("user32.dll")]',
            '    public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);',
            '    [DllImport("user32.dll")]',
            '    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);',
            '    [DllImport("user32.dll", CharSet = CharSet.Unicode)]',
            '    public static extern int GetClassName(IntPtr hWnd, StringBuilder buf, int max);',
            '    [DllImport("user32.dll", CharSet = CharSet.Unicode)]',
            '    public static extern int GetWindowText(IntPtr hWnd, StringBuilder buf, int max);',
            '    [DllImport("user32.dll")]',
            '    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);',
            '    [DllImport("user32.dll")]',
            '    public static extern bool IsWindowVisible(IntPtr hWnd);',
            '}',
            '"@',
            'function ShowAllWindows {',
            '    $script:anyVisible = $false',
            '    $script:anyFound = $false',
            '    [void][RStudioWin]::EnumWindows({',
            '        param($hWnd, $lParam)',
            '        [uint32]$wpid = 0',
            '        [RStudioWin]::GetWindowThreadProcessId($hWnd, [ref]$wpid) | Out-Null',
            '        if ($script:pidSet.ContainsKey([int]$wpid)) {',
            '            $cls = New-Object System.Text.StringBuilder 256',
            '            [RStudioWin]::GetClassName($hWnd, $cls, 256) | Out-Null',
            '            if ($cls.ToString() -eq "Chrome_WidgetWin_1") {',
            '                $ttl = New-Object System.Text.StringBuilder 256',
            '                [RStudioWin]::GetWindowText($hWnd, $ttl, 256) | Out-Null',
            '                if ($ttl.ToString().Length -gt 0) {',
            '                    $script:anyFound = $true',
            '                    if (-not [RStudioWin]::IsWindowVisible($hWnd)) {',
            '                        [RStudioWin]::ShowWindow($hWnd, 9) | Out-Null',
            '                    }',
            '                    if ([RStudioWin]::IsWindowVisible($hWnd)) {',
            '                        $script:anyVisible = $true',
            '                    }',
            '                }',
            '            }',
            '        }',
            '        return $true',
            '    }, [IntPtr]::Zero)',
            '}',
            '$pidSet = @{ $RootPid = $true }',
            '$found = $false',
            'for ($i = 0; $i -lt 200; $i++) {',
            '    Start-Sleep -Milliseconds 100',
            '    $cim = Get-CimInstance Win32_Process -Filter "Name=''rstudio.exe''" -EA SilentlyContinue',
            '    foreach ($p in $cim) {',
            '        if ($pidSet.ContainsKey([int]$p.ParentProcessId)) {',
            '            $pidSet[[int]$p.ProcessId] = $true',
            '        }',
            '    }',
            '    if ($pidSet.Count -lt 2) { continue }',
            '    ShowAllWindows',
            '    if ($anyFound) { $found = $true }',
            '    if ($anyVisible) {',
            '        for ($g = 0; $g -lt 50; $g++) {',
            '            Start-Sleep -Milliseconds 100',
            '            ShowAllWindows',
            '        }',
            '        Write-Output "OK"',
            '        exit 0',
            '    }',
            '}',
            'if ($found) { Write-Output "SHOW_FAILED" } else { Write-Output "TIMEOUT" }',
        ]
        writefile(code, ps_script_path)
    endif

    var script = ps_script_path
    job_start(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', script, string(pid)], {
        out_cb: (ch: channel, msg: string) => {
            var m = trim(msg)
            if m ==# 'TIMEOUT'
                g:RWarningMsg('RStudio window did not appear within 20 seconds')
            elseif m ==# 'SHOW_FAILED'
                g:RWarningMsg('RStudio window found but could not be made visible')
            endif
        },
        exit_cb: (j: job, status: number) => {
            delete(script)
        },
    })
enddef

def g:SignalToRStudio()
    if g:IsJobRunning("RStudio")
        var pid = job_info(g:rplugin.jobs['RStudio']).process
        if has("win32")
            # /T kills the entire Electron process tree
            system('taskkill /PID ' .. pid .. ' /T /F')
        else
            system('kill -9 ' .. pid)
        endif
    endif
    g:rplugin.jobs["RStudio"] = "no"
enddef

def g:SendCmdToRStudio(...args: list<any>): number
    if !g:IsJobRunning("RStudio")
        g:RWarningMsg("Is RStudio running?")
        return 0
    endif
    var cmd = substitute(args[0], '"', '\\"', "g")
    g:SendToVimcom("E", 'sendToConsole("' .. cmd .. '", execute=TRUE)')
    return 1
enddef

g:R_bracketed_paste = 0
g:R_parenblock = 0
