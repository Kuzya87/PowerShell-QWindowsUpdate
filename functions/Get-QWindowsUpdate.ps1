function Get-QWindowsUpdate {
    <#
    .SYNOPSIS
        Получение информации об обновлениях Windows, доступных для установки.
    .DESCRIPTION
        Функция-обёртка над классом [QWindowsUpdate], выполняющая поиск обновлений,
        доступных для установки на этом компьютере, через штатный Windows Update Agent (WUA).
        Без параметров возвращает массив объектов [QWindowsUpdate[]] в конвейер.
        С параметром -Info выводит удобную для человека таблицу с результатами поиска
        в консоль, ничего не возвращая в конвейер.
    .PARAMETER Info
        Вместо возврата объектов [QWindowsUpdate[]] в конвейер, выводит в консоль таблицу
        с найденными обновлениями (номера KB и название) и сводку о необходимости
        перезагрузки при условии установки всех найденных обновлений.
    .EXAMPLE
        PS C:\> $Updates = Get-QWindowsUpdate

        Выполняет поиск доступных обновлений и сохраняет найденные объекты [QWindowsUpdate[]]
        в переменную $Updates.
    .EXAMPLE
        PS C:\> Get-QWindowsUpdate -Info

        Выполняет поиск доступных обновлений и выводит в консоль удобную для человека таблицу
        с результатами, ничего не возвращая в конвейер.
    .INPUTS
        Отсутствуют.
    .OUTPUTS
        QWindowsUpdate[] - только при вызове без параметра -Info.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$Info
    )

    begin {
        $ErrorActionPreference = "Stop"
        Write-Host -Object "Начало выполнения: $(Get-Date)" -ForegroundColor "Blue"
        [System.Diagnostics.Stopwatch]$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    }

    process {
        try {
            Write-Verbose -Message "Поиск обновлений, доступных для установки..."
            [QWindowsUpdate[]]$Updates = [QWindowsUpdate]::StartScan()

            if ($Info) {
                if (-not $Updates) {
                    Write-Host -Object "Обновления, доступные для установки, не найдены."
                }
                else {
                    Write-Verbose -Message "Формирование таблицы для вывода в консоль..."
                    $Updates | Select-Object -Property @{Name = "Номера KB"; Expression = { $_.KBArticleIDs -join ", " } }, @{Name = "Название"; Expression = { $_.Title } } | Format-Table -AutoSize -Wrap | Out-Host

                    [bool]$OverallRebootRequired = [bool]($Updates | Where-Object -Property "RebootRequired" -EQ $true)
                    if ($OverallRebootRequired) {
                        Write-Host -Object "При установке всех найденных обновлений потребуется перезагрузка компьютера."
                    }
                    else {
                        Write-Host -Object "При установке всех найденных обновлений перезагрузка компьютера не потребуется."
                    }
                }
            }
            else {
                return $Updates
            }
        }
        finally {
            # В "finally", чтобы сообщение о затраченном времени выводилось при любом исходе, включая ошибку поиска
            $Stopwatch.Stop()
            Write-Host -Object "Затраченное время: $($Stopwatch.Elapsed.ToString('hh\:mm\:ss'))" -ForegroundColor "Blue"
        }
    }

    end {}
}
