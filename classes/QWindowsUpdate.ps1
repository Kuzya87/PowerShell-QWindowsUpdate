class QWindowsUpdate {
    # Номера статей базы знаний (KB), к которым относится обновление
    [string[]]$KBArticleIDs
    # Заголовок обновления
    [string]$Title
    # Описание обновления
    [string]$Description
    # Ссылка на страницу поддержки обновления
    [string]$SupportUrl
    # Уникальный идентификатор обновления в каталоге Windows Update
    [guid]$UpdateID
    # Категории, к которым относится обновление
    [string[]]$Categories
    # Уровень серьёзности обновления по классификации MSRC
    [string]$MsrcSeverity
    # Размер обновления в мегабайтах (округлённый до сотых)
    [double]$SizeMb
    # Признак того, что обновление уже было загружено на момент поиска
    [bool]$Downloaded
    # Вероятная необходимость перезагрузки согласно описанию обновления
    [bool]$RebootRequired
    # Исходный COM-объект обновления (IUpdate) - хранится, чтобы Install() и Download()
    # могли работать с тем же самым обновлением без повторного поиска
    hidden [System.__ComObject]$ComUpdateObject

    ################
    # КОНСТРУКТОРЫ #
    ################

    # Конструктор пустого объекта
    QWindowsUpdate() {}

    ###########
    # МЕТОДЫ  #
    ###########

    # Возвращает заголовок обновления вместо имени класса
    [string] ToString() {
        return $this.Title
    }

    # Проверка наличия у текущей сессии PowerShell прав администратора
    hidden static [bool] IsAdministrator() {
        [System.Security.Principal.WindowsIdentity]$CurrentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        [System.Security.Principal.WindowsPrincipal]$CurrentPrincipal = [System.Security.Principal.WindowsPrincipal]::new($CurrentIdentity)
        return $CurrentPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    # Преобразование COM-объекта IUpdate в объект [QWindowsUpdate]
    hidden static [QWindowsUpdate] ConvertFromComUpdate([System.__ComObject]$ComUpdate) {
        Write-Verbose -Message "Преобразование найденного обновления '$($ComUpdate.Title)' в объект [QWindowsUpdate]..."

        [QWindowsUpdate]$UpdateObject = [QWindowsUpdate]::new()

        $UpdateObject.KBArticleIDs = [string[]]@($ComUpdate.KBArticleIDs)
        $UpdateObject.Title = [string]$ComUpdate.Title
        $UpdateObject.Description = [string]$ComUpdate.Description
        $UpdateObject.SupportUrl = [string]$ComUpdate.SupportUrl
        $UpdateObject.UpdateID = [guid]$ComUpdate.Identity.UpdateID
        $UpdateObject.Categories = [string[]]@($ComUpdate.Categories | ForEach-Object -Process { $_.Name })
        $UpdateObject.MsrcSeverity = [string]$ComUpdate.MsrcSeverity

        [double]$MaxSizeBytes = [double]$ComUpdate.MaxDownloadSize
        [double]$MinSizeBytes = [double]$ComUpdate.MinDownloadSize
        [double]$SizeBytes = if ($MaxSizeBytes -gt 0) { $MaxSizeBytes } else { $MinSizeBytes }
        $UpdateObject.SizeMb = [System.Math]::Round(($SizeBytes / 1MB), 2)

        $UpdateObject.Downloaded = [bool]$ComUpdate.IsDownloaded
        $UpdateObject.RebootRequired = ([int]$ComUpdate.InstallationBehavior.RebootBehavior -ne 0)

        $UpdateObject.ComUpdateObject = $ComUpdate

        return $UpdateObject
    }

    # Поиск всех обновлений, доступных для установки на этом компьютере
    static [QWindowsUpdate[]] StartScan() {
        Write-Verbose -Message "Создание сессии Windows Update Agent (Microsoft.Update.Session)..."
        [System.__ComObject]$Session = New-Object -ComObject "Microsoft.Update.Session"

        Write-Verbose -Message "Создание объекта поиска обновлений (IUpdateSearcher)..."
        [System.__ComObject]$Searcher = $Session.CreateUpdateSearcher()

        [string]$SearchCriteria = "IsInstalled=0 and IsHidden=0"
        Write-Verbose -Message "Поиск обновлений по критерию: '$SearchCriteria'..."
        [System.__ComObject]$SearchResult = $Searcher.Search($SearchCriteria)

        [System.Collections.Generic.List[QWindowsUpdate]]$Result = [System.Collections.Generic.List[QWindowsUpdate]]::new()
        foreach ($ComUpdate in $SearchResult.Updates) {
            Write-Verbose -Message "Найдено обновление: '$($ComUpdate.Title)'."
            $Result.Add([QWindowsUpdate]::ConvertFromComUpdate($ComUpdate))
        }

        if ($Result.Count -eq 0) {
            Write-Verbose -Message "Доступные для установки обновления не найдены."
            return $null
        }

        Write-Verbose -Message "Поиск обновлений завершён. Найдено обновлений: $($Result.Count)."
        return $Result.ToArray()
    }

    # Загрузка (при необходимости) и установка обновления
    [bool] Install() {
        Write-Verbose -Message "Проверка прав администратора перед установкой обновления '$($this.Title)'..."
        if (-not [QWindowsUpdate]::IsAdministrator()) {
            throw "Для установки обновления '$($this.Title)' требуются права администратора. Запустите PowerShell от имени администратора."
        }

        [System.__ComObject]$Session = New-Object -ComObject "Microsoft.Update.Session"
        [System.__ComObject]$UpdateColl = New-Object -ComObject "Microsoft.Update.UpdateColl"
        $UpdateColl.Add($this.ComUpdateObject) | Out-Null

        if (-not $this.ComUpdateObject.EulaAccepted) {
            Write-Verbose -Message "Принятие лицензионного соглашения обновления '$($this.Title)'..."
            $this.ComUpdateObject.AcceptEula()
        }

        if (-not $this.Downloaded) {
            Write-Verbose -Message "Обновление '$($this.Title)' ещё не загружено. Выполняется загрузка..."
            [System.__ComObject]$Downloader = $Session.CreateUpdateDownloader()
            $Downloader.Updates = $UpdateColl

            Write-Progress -Activity "Установка обновления '$($this.Title)'" -Status "Загрузка..." -PercentComplete 0
            [System.__ComObject]$DownloadResult = $Downloader.Download()

            if ($DownloadResult.ResultCode -ne 2) {
                Write-Progress -Activity "Установка обновления '$($this.Title)'" -Completed
                throw "Не удалось загрузить обновление '$($this.Title)'. Код результата WUA: $($DownloadResult.ResultCode)."
            }
            $this.Downloaded = $true
            Write-Verbose -Message "Обновление '$($this.Title)' успешно загружено."
        }

        Write-Verbose -Message "Установка обновления '$($this.Title)'..."
        [System.__ComObject]$Installer = $Session.CreateUpdateInstaller()
        $Installer.Updates = $UpdateColl

        Write-Progress -Activity "Установка обновления '$($this.Title)'" -Status "Установка..." -PercentComplete 50
        [System.__ComObject]$InstallResult = $Installer.Install()
        Write-Progress -Activity "Установка обновления '$($this.Title)'" -Completed

        if ($InstallResult.ResultCode -ne 2) {
            throw "Не удалось установить обновление '$($this.Title)'. Код результата WUA: $($InstallResult.ResultCode)."
        }
        Write-Verbose -Message "Обновление '$($this.Title)' успешно установлено."

        Write-Verbose -Message "Проверка реального состояния системы на предмет необходимости перезагрузки..."
        [System.__ComObject]$SystemInfo = New-Object -ComObject "Microsoft.Update.SystemInfo"
        [bool]$RebootIsRequired = [bool]$SystemInfo.RebootRequired
        Write-Verbose -Message "Необходимость перезагрузки компьютера: $RebootIsRequired."

        return $RebootIsRequired
    }

    # Скачивание обновления в указанный локальный каталог
    [void] Download([string]$Path) {
        Write-Verbose -Message "Проверка существования каталога '$Path'..."
        if (-not (Test-Path -Path $Path -PathType "Container")) {
            throw "Каталог '$Path' не существует. Укажите путь к существующему локальному каталогу."
        }

        Write-Verbose -Message "Проверка прав администратора перед скачиванием обновления '$($this.Title)'..."
        if (-not [QWindowsUpdate]::IsAdministrator()) {
            throw "Для скачивания обновления '$($this.Title)' требуются права администратора. Запустите PowerShell от имени администратора."
        }

        if (-not $this.ComUpdateObject.EulaAccepted) {
            Write-Verbose -Message "Принятие лицензионного соглашения обновления '$($this.Title)'..."
            $this.ComUpdateObject.AcceptEula()
        }

        if (-not $this.Downloaded) {
            Write-Verbose -Message "Обновление '$($this.Title)' ещё не загружено в кэш Windows Update. Выполняется загрузка..."
            [System.__ComObject]$Session = New-Object -ComObject "Microsoft.Update.Session"
            [System.__ComObject]$UpdateColl = New-Object -ComObject "Microsoft.Update.UpdateColl"
            $UpdateColl.Add($this.ComUpdateObject) | Out-Null

            [System.__ComObject]$Downloader = $Session.CreateUpdateDownloader()
            $Downloader.Updates = $UpdateColl

            Write-Progress -Activity "Скачивание обновления '$($this.Title)'" -Status "Загрузка в кэш Windows Update..." -PercentComplete 0
            [System.__ComObject]$DownloadResult = $Downloader.Download()
            Write-Progress -Activity "Скачивание обновления '$($this.Title)'" -Completed

            if ($DownloadResult.ResultCode -ne 2) {
                throw "Не удалось загрузить обновление '$($this.Title)'. Код результата WUA: $($DownloadResult.ResultCode)."
            }
            $this.Downloaded = $true
            Write-Verbose -Message "Обновление '$($this.Title)' успешно загружено в кэш Windows Update."
        }

        Write-Verbose -Message "Определение оригинальных имён файлов обновления '$($this.Title)'..."
        foreach ($Content in $this.ComUpdateObject.DownloadContents) {
            [string]$FileName = [System.Uri]::new([string]$Content.DownloadUrl).Segments[-1]
            [string]$DestinationFile = Join-Path -Path $Path -ChildPath $FileName
            if (Test-Path -Path $DestinationFile -PathType "Leaf") {
                Write-Verbose -Message "Файл '$DestinationFile' уже существует и будет перезаписан."
                Remove-Item -Path $DestinationFile -Force
            }
        }

        Write-Verbose -Message "Перенос файлов обновления '$($this.Title)' из кэша Windows Update в каталог '$Path'..."
        Write-Progress -Activity "Скачивание обновления '$($this.Title)'" -Status "Перенос в '$Path'..." -PercentComplete 50
        $this.ComUpdateObject.CopyFromCache($Path, $false)
        Write-Progress -Activity "Скачивание обновления '$($this.Title)'" -Completed

        Write-Verbose -Message "Обновление '$($this.Title)' скачано в каталог '$Path'."
    }
}
