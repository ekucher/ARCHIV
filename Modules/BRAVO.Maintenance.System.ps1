# ==============================================================================
# BRAVO.Maintenance.System.ps1
# Автоматично винесені функції з BRAVO_MAINTENANCE.ps1
# ==============================================================================

function Invoke-AutoShutdown {
    param([int]$Timeout = 120)
    
    Write-MaintenanceLog -Message "=== АВТОМАТИЧНЕ ВИМКНЕННЯ СИСТЕМИ ==="

    try {
        $shutdownCommand = "shutdown /s /t $Timeout /c `"Система буде вимкнена через $Timeout секунд через завершення обслуговування BravoSoft. Для скасування виконайте: shutdown /a`""
        
        Write-MaintenanceLog "Ініціювання вимкнення системи..." -Level "INFO"
        
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $shutdownCommand" -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-Success "Система буде вимкнена через $Timeout секунд"
            
            Add-Type -AssemblyName System.Windows.Forms
            
            $message = "Система буде вимкнена через $Timeout секунд через завершення обслуговування BravoSoft.`n`nБажаєте скасувати вимкнення?"
            $caption = "BravoSoft - Завершення обслуговування"
            $buttons = [System.Windows.Forms.MessageBoxButtons]::YesNo
            $icon = [System.Windows.Forms.MessageBoxIcon]::Question
            
            $result = [System.Windows.Forms.MessageBox]::Show($message, $caption, $buttons, $icon)
            
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                Write-MaintenanceLog "Користувач скасував вимкнення системи" -Level "INFO"
                
                $cancelProcess = Start-Process "shutdown" -ArgumentList "/a" -Wait -PassThru -NoNewWindow
                
                if ($cancelProcess.ExitCode -eq 0) {
                    Write-Success "Вимкнення успішно скасовано"
                    [System.Windows.Forms.MessageBox]::Show("Вимкнення скасовано! Система продовжить роботу.", "BravoSoft", 
                        [System.Windows.Forms.MessageBoxButtons]::OK, 
                        [System.Windows.Forms.MessageBoxIcon]::Information)
                } else {
                    Write-ErrorLog "Не вдалося скасувати вимкнення"
                    [System.Windows.Forms.MessageBox]::Show("Не вдалося скасувати вимкнення. Спробуйте виконати команду вручну: shutdown /a", "Помилка", 
                        [System.Windows.Forms.MessageBoxButtons]::OK, 
                        [System.Windows.Forms.MessageBoxIcon]::Warning)
                }
            } else {
                Write-MaintenanceLog "Користувач підтвердив вимкнення системи" -Level "INFO"
                [System.Windows.Forms.MessageBox]::Show("Система буде вимкнена через $Timeout секунд.", "BravoSoft", 
                    [System.Windows.Forms.MessageBoxButtons]::OK, 
                    [System.Windows.Forms.MessageBoxIcon]::Information)
            }
        } else {
            Write-ErrorLog "Помилка ініціювання вимкнення системи. Код помилки: $($process.ExitCode)"
        }
    }
    catch {
        Write-ErrorLog "Помилка під час спроби вимкнення системи: $($_.Exception.Message)"
    }
}
