function Install-QWindowsUpdate {
    <#
    .SYNOPSIS
        Установка обновлений Windows.
    .DESCRIPTION
        Функция-обёртка над классом [QWindowsUpdate], выполняющая установку обновлений Windows
        через штатный Windows Update Agent (WUA).
        С параметром -AllAvailable выполняется поиск и установка всех доступных обновлений.
        С параметром -Update устанавливаются ранее найденные объекты [QWindowsUpdate],
        в том числе переданные по конвейеру.
        В обоих случаях в конвейер возвращается один объект [bool] об общей результирующей
        необходимости перезагрузки компьютера.
    .PARAMETER AllAvailable
        Выполняет поиск всех доступных обновлений и устанавливает их все.
        Взаимоисключающий с параметром -Update.
    .PARAMETER Update
        Один или несколько объектов обновлений [QWindowsUpdate] для установки.
        Поддерживает передачу по конвейеру.
        Взаимоисключающий с параметром -AllAvailable.
    .EXAMPLE
        PS C:\> Install-QWindowsUpdate -AllAvailable

        Выполняет поиск всех доступных обновлений, устанавливает их все и возвращает [bool]
        об общей результирующей необходимости перезагрузки компьютера.
    .EXAMPLE
        PS C:\> $Updates = Get-QWindowsUpdate
        PS C:\> $Updates | Install-QWindowsUpdate

        Устанавливает ранее найденные обновления, переданные по конвейеру, и возвращает [bool]
        об общей результирующей необходимости перезагрузки компьютера.
    .EXAMPLE
        PS C:\> $Updates = Get-QWindowsUpdate
        PS C:\> Install-QWindowsUpdate -Update $Updates[0]

        Устанавливает одно конкретное обновление из ранее найденного массива.
    .INPUTS
        QWindowsUpdate[] - при использовании параметра -Update.
    .OUTPUTS
        bool
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ParameterSetName = "AllAvailable")]
        [switch]$AllAvailable,
        [Parameter(Mandatory = $true, ParameterSetName = "ByUpdate", ValueFromPipeline = $true)]
        [QWindowsUpdate[]]$Update
    )

    begin {
        $ErrorActionPreference = "Stop"
        Write-Host -Object "Начало выполнения: $(Get-Date)" -ForegroundColor "Blue"
        [System.Diagnostics.Stopwatch]$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        [System.Collections.Generic.List[QWindowsUpdate]]$UpdatesToInstall = [System.Collections.Generic.List[QWindowsUpdate]]::new()
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq "AllAvailable") {
            Write-Verbose -Message "Поиск всех обновлений, доступных для установки..."
            [QWindowsUpdate[]]$FoundUpdates = [QWindowsUpdate]::StartScan()
            if ($FoundUpdates) {
                $UpdatesToInstall.AddRange($FoundUpdates)
            }
        }
        else {
            foreach ($SingleUpdate in $Update) {
                $UpdatesToInstall.Add($SingleUpdate)
            }
        }
    }

    end {
        [bool]$OverallRebootRequired = $false

        try {
            if ($UpdatesToInstall.Count -eq 0) {
                Write-Verbose -Message "Обновления для установки не найдены."
            }
            else {
                foreach ($SingleUpdate in $UpdatesToInstall) {
                    Write-Verbose -Message "Установка обновления '$SingleUpdate'..."
                    [bool]$RebootRequired = $SingleUpdate.Install()
                    if ($RebootRequired) {
                        $OverallRebootRequired = $true
                    }
                }
            }
        }
        finally {
            # В "finally", чтобы сообщение о затраченном времени выводилось при любом исходе, включая ошибку установки
            $Stopwatch.Stop()
            Write-Host -Object "Затраченное время: $($Stopwatch.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor "Blue"
        }

        return $OverallRebootRequired
    }
}
