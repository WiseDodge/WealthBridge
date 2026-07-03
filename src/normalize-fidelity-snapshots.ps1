param(
    [string]$InputFolder = (Join-Path (Split-Path $PSScriptRoot -Parent) 'raw'),
    [string]$OutputFolder = (Join-Path (Split-Path $PSScriptRoot -Parent) 'normalized-holdings'),
    [switch]$AggregateSameSymbolRows
)

$monthMap = @{
    Jan = 1
    Feb = 2
    Mar = 3
    Apr = 4
    May = 5
    Jun = 6
    Jul = 7
    Aug = 8
    Sep = 9
    Oct = 10
    Nov = 11
    Dec = 12
}

$canonicalColumns = @(
    'Date',
    'Account Number',
    'Account Name',
    'Symbol',
    'Description',
    'Current value',
    'Quantity',
    'Average cost basis',
    'Cost basis total',
    'Account type',
    'Currency',
    'Total gain/loss $',
    'Total gain/loss %',
    'Exp ratio (net)',
    'YTD',
    'Sector'
)

if (-not (Test-Path -LiteralPath $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}

function Get-ResolvedPath {
    param([string]$Path)

    return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Get-SnapshotDate {
    param([string]$Path)

    $lines = @(Get-Content -LiteralPath $Path)

    $name = Split-Path -Leaf $Path
    if ($name -match 'Portfolio_Positions_(?<mon>[A-Za-z]{3})-(?<day>\d{2})-(?<year>\d{4})') {
        $month = $monthMap[$Matches.mon]
        if ($month) {
            return [datetime]::new([int]$Matches.year, $month, [int]$Matches.day).ToString('yyyy-MM-dd')
        }
    }

    $footerLine = $lines | Where-Object { $_ -match '^"Date downloaded\s+' } | Select-Object -First 1
    if ($footerLine -and $footerLine -match 'Date downloaded\s+(?<mon>[A-Za-z]{3})-(?<day>\d{2})-(?<year>\d{4})') {
        $month = $monthMap[$Matches.mon]
        if ($month) {
            return [datetime]::new([int]$Matches.year, $month, [int]$Matches.day).ToString('yyyy-MM-dd')
        }
    }

    throw "Unable to determine snapshot date for $Path"
}

function Get-RowValue {
    param(
        [psobject]$Row,
        [string[]]$Names,
        [string]$Default = ''
    )

    foreach ($name in $Names) {
        foreach ($property in $Row.PSObject.Properties) {
            if ($property.Name.Trim() -ieq $name) {
                if ($null -ne $property.Value) {
                    return ([string]$property.Value).Trim()
                }
            }
        }
    }

    return $Default
}

function Test-IsCashRow {
    param(
        [string]$Symbol,
        [string]$AccountName
    )

    return (
        $Symbol -ieq 'SPAXX' -or
        $Symbol -ieq 'SPAXX**' -or
        $AccountName -like 'Cash Management*'
    )
}

function Get-CashDescription {
    param(
        [string]$Symbol,
        [string]$AccountName
    )

    if ($AccountName -like 'Cash Management*') {
        return 'Cash (Cash Management)'
    }

    if ($Symbol -ieq 'SPAXX' -or $Symbol -ieq 'SPAXX**') {
        return 'Cash (SPAXX)'
    }

    return 'Cash'
}

function Convert-ToDecimalValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [decimal]0
    }

    $cleanValue = $Value -replace '[^0-9\.-]', ''
    if ([string]::IsNullOrWhiteSpace($cleanValue) -or $cleanValue -eq '-' -or $cleanValue -eq '.') {
        return [decimal]0
    }

    return [decimal]$cleanValue
}

function Get-ExportTimestamp {
    param([string]$Path)

    $lines = @(Get-Content -LiteralPath $Path)
    $footerLine = $lines | Where-Object { $_ -match '^"Date downloaded\s+' } | Select-Object -First 1
    if ($footerLine -and $footerLine -match 'Date downloaded\s+(?<mon>[A-Za-z]{3})-(?<day>\d{2})-(?<year>\d{4})\s+(?<hour>\d{1,2}):(?<minute>\d{2})\s*(?<ampm>a\.m\.|p\.m\.)') {
        $month = $monthMap[$Matches.mon]
        if ($month) {
            $hour = [int]$Matches.hour
            $minute = [int]$Matches.minute
            $ampm = $Matches.ampm
            if ($ampm -ieq 'p.m.' -and $hour -lt 12) { $hour += 12 }
            if ($ampm -ieq 'a.m.' -and $hour -eq 12) { $hour = 0 }
            return [datetime]::new([int]$Matches.year, $month, [int]$Matches.day, $hour, $minute, 0)
        }
    }

    return [datetime]::MinValue
}

function Format-File {
    param(
        [string]$Path,
        [string]$DateValue
    )

    $lines = @(Get-Content -LiteralPath $Path)
    if ($lines.Count -lt 2) {
        return @()
    }

    $dataLines = New-Object System.Collections.Generic.List[string]
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line.TrimStart().StartsWith('"')) {
            break
        }
        $dataLines.Add($line)
    }

    if ($dataLines.Count -eq 0) {
        return @()
    }

    $csvInput = @($lines[0]) + $dataLines.ToArray()
    $parsedRows = $csvInput | ConvertFrom-Csv

    foreach ($row in $parsedRows) {
        $rawSymbol = Get-RowValue -Row $row -Names @('Symbol')
        $accountName = Get-RowValue -Row $row -Names @('Account Name')
        $isCashRow = Test-IsCashRow -Symbol $rawSymbol -AccountName $accountName
        $symbol = if ($isCashRow) { '$CASH' } elseif ($rawSymbol -ieq 'SPAXX**') { 'SPAXX' } else { $rawSymbol }
        if ([string]::IsNullOrWhiteSpace($symbol) -and [string]::IsNullOrWhiteSpace($accountName)) {
            continue
        }
        if ($symbol -ieq 'Pending activity' -or $accountName -ieq 'Pending activity') {
            continue
        }

        $currentValue = Get-RowValue -Row $row -Names @('Current value', 'Current Value')
        $quantity = Get-RowValue -Row $row -Names @('Quantity')
        $averageCostBasis = Get-RowValue -Row $row -Names @('Average cost basis', 'Average Cost Basis')
        $costBasisTotal = Get-RowValue -Row $row -Names @('Cost basis total', 'Cost Basis Total')
        $accountType = Get-RowValue -Row $row -Names @('Account type', 'Type', 'Account Type')

        if ($isCashRow) {
            $cashBalance = Convert-ToDecimalValue -Value $currentValue
            $currentValue = ('$' + ([math]::Round($cashBalance, 2).ToString([System.Globalization.CultureInfo]::InvariantCulture)))
            $quantity = ([math]::Round($cashBalance, 2)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            $averageCostBasis = '1'
            $costBasisTotal = $currentValue
            $accountType = 'Cash'
        }

        [pscustomobject]@{
            'Date' = $DateValue
            'Account Number' = Get-RowValue -Row $row -Names @('Account Number')
            'Account Name' = $accountName
            'Symbol' = $symbol
            'Description' = if ($isCashRow) { Get-CashDescription -Symbol $rawSymbol -AccountName $accountName } else { Get-RowValue -Row $row -Names @('Description') }
            'Current value' = $currentValue
            'Quantity' = $quantity
            'Average cost basis' = $averageCostBasis
            'Cost basis total' = $costBasisTotal
            'Account type' = $accountType
            'Currency' = Get-RowValue -Row $row -Names @('Currency') -Default 'USD'
            'Total gain/loss $' = if ($isCashRow) { '$0' } else { Get-RowValue -Row $row -Names @('Total gain/loss $', 'Total Gain/Loss Dollar') }
            'Total gain/loss %' = if ($isCashRow) { '' } else { Get-RowValue -Row $row -Names @('Total gain/loss %', 'Total Gain/Loss Percent') }
            'Exp ratio (net)' = Get-RowValue -Row $row -Names @('Exp ratio (net)', 'Exp Ratio (Net)')
            'YTD' = Get-RowValue -Row $row -Names @('YTD')
            'Sector' = Get-RowValue -Row $row -Names @('Sector')
        }
    }
}

function Merge-SameSymbolRows {
    param([object[]]$Rows)

    $groups = $Rows | Group-Object {
        @($_.'Date', $_.'Account Number', $_.'Account Name', $_.Symbol) -join '||'
    }

    foreach ($group in $groups) {
        $items = @($group.Group)
        $accountTypes = @($items | ForEach-Object { $_.'Account type' } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        $descriptions = @($items | ForEach-Object { $_.Description } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        $currencies = @($items | ForEach-Object { $_.Currency } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
        $totalQuantity = [decimal]0
        $totalCurrentValue = [decimal]0
        $totalCostBasis = [decimal]0
        $totalGainDollar = [decimal]0

        foreach ($item in $items) {
            $totalQuantity += Convert-ToDecimalValue -Value $item.Quantity
            $totalCurrentValue += Convert-ToDecimalValue -Value $item.'Current value'
            $totalCostBasis += Convert-ToDecimalValue -Value $item.'Cost basis total'
            $totalGainDollar += Convert-ToDecimalValue -Value $item.'Total gain/loss $'
        }

        $averageCostBasis = ''
        if ($totalQuantity -gt 0) {
            $averageCostBasis = ([math]::Round(($totalCostBasis / $totalQuantity), 6)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        }

        $gainPercent = ''
        if ($totalCostBasis -gt 0) {
            $gainPercent = ([math]::Round((($totalGainDollar / $totalCostBasis) * 100), 2)).ToString([System.Globalization.CultureInfo]::InvariantCulture) + '%'
        }

        [pscustomobject]@{
            'Date' = $items[0].Date
            'Account Number' = $items[0].'Account Number'
            'Account Name' = $items[0].'Account Name'
            'Symbol' = $items[0].Symbol
            'Description' = ($descriptions | Select-Object -First 1)
            'Current value' = ('$' + ([math]::Round($totalCurrentValue, 2).ToString([System.Globalization.CultureInfo]::InvariantCulture)))
            'Quantity' = ([math]::Round($totalQuantity, 6)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
            'Average cost basis' = $averageCostBasis
            'Cost basis total' = ('$' + ([math]::Round($totalCostBasis, 2).ToString([System.Globalization.CultureInfo]::InvariantCulture)))
            'Account type' = if ($accountTypes.Count -gt 1) { 'Combined' } else { ($accountTypes | Select-Object -First 1) }
            'Currency' = ($currencies | Select-Object -First 1)
            'Total gain/loss $' = ('$' + ([math]::Round($totalGainDollar, 2).ToString([System.Globalization.CultureInfo]::InvariantCulture)))
            'Total gain/loss %' = $gainPercent
            'Exp ratio (net)' = ($items | ForEach-Object { $_.'Exp ratio (net)' } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
            'YTD' = ($items | ForEach-Object { $_.YTD } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
            'Sector' = ($items | ForEach-Object { $_.Sector } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
        }
    }
}

$rawFiles = Get-ChildItem -LiteralPath $InputFolder -Filter 'Portfolio_Positions_*.csv' |
    Where-Object { $_.Name -notmatch '_Sample\.csv$' } |
    Where-Object {
        $resolvedDirectory = Get-ResolvedPath -Path $_.DirectoryName
        $resolvedOutput = Get-ResolvedPath -Path $OutputFolder
        $resolvedDirectory -ne $resolvedOutput -and
        $_.BaseName -notmatch '^Portfolio_Positions_\d{4}-\d{2}-\d{2}$'
    } |
    Sort-Object Name

$groupedFiles = $rawFiles | Group-Object { Get-SnapshotDate -Path $_.FullName }

$summary = foreach ($group in $groupedFiles) {
    $profiles = foreach ($file in $group.Group) {
        $rows = @(Format-File -Path $file.FullName -DateValue $group.Name)
        [pscustomobject]@{
            File = $file
            Rows = $rows
            Signature = ($rows | ForEach-Object {
                @(
                    $_.'Date',
                    $_.'Account Number',
                    $_.'Account Name',
                    $_.Symbol,
                    $_.Description,
                    $_.'Current value',
                    $_.Quantity,
                    $_.'Average cost basis',
                    $_.'Cost basis total',
                    $_.'Account type',
                    $_.Currency,
                    $_.'Total gain/loss $',
                    $_.'Total gain/loss %',
                    $_.'Exp ratio (net)',
                    $_.YTD,
                    $_.Sector
                ) -join '||'
            }) -join '###'
            ExportTimestamp = Get-ExportTimestamp -Path $file.FullName
            AccountScopes = @($rows | ForEach-Object { @($_.'Account Number', $_.'Account Name') -join '||' } | Sort-Object -Unique)
        }
    }

    $selectedProfiles = @()
    $selectionMode = 'Merged'

    if ($profiles.Count -le 1) {
        $selectedProfiles = @($profiles)
    }
    elseif (@($profiles.Signature | Sort-Object -Unique).Count -eq 1) {
        $selectedProfiles = @($profiles | Select-Object -First 1)
        $selectionMode = 'ExactDuplicate'
    }
    else {
        $hasAccountScopeOverlap = $false
        for ($i = 0; $i -lt $profiles.Count; $i++) {
            for ($j = $i + 1; $j -lt $profiles.Count; $j++) {
                if ((@($profiles[$i].AccountScopes) | Where-Object { $_ -in $profiles[$j].AccountScopes }).Count -gt 0) {
                    $hasAccountScopeOverlap = $true
                    break
                }
            }
            if ($hasAccountScopeOverlap) { break }
        }

        if ($hasAccountScopeOverlap) {
            $selectedProfiles = @($profiles | Sort-Object ExportTimestamp, @{ Expression = { $_.File.LastWriteTime } } | Select-Object -Last 1)
            $selectionMode = 'LatestOnly'
        }
        else {
            $selectedProfiles = @($profiles)
            $selectionMode = 'ComplementaryMerge'
        }
    }

    $normalizedRows = New-Object System.Collections.Generic.List[object]
    foreach ($snapshotProfile in $selectedProfiles) {
        foreach ($row in $snapshotProfile.Rows) {
            $normalizedRows.Add($row)
        }
    }

    $normalizedOutputRows = @($normalizedRows | ForEach-Object { $_ })
    if ($AggregateSameSymbolRows) {
        $normalizedOutputRows = @(Merge-SameSymbolRows -Rows $normalizedRows)
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $finalRows = New-Object System.Collections.Generic.List[object]
    foreach ($row in $normalizedOutputRows) {
        $key = ($canonicalColumns | ForEach-Object { [string]$row.$_ }) -join '||'
        if ($seen.Add($key)) {
            $finalRows.Add($row)
        }
    }

    $outputPath = Join-Path $OutputFolder ("Portfolio_Positions_{0}.csv" -f $group.Name)
    $finalRows |
        Select-Object $canonicalColumns |
        Export-Csv -LiteralPath $outputPath -NoTypeInformation -Encoding utf8

    [pscustomobject]@{
        SnapshotDate = $group.Name
        SourceFiles = ($group.Group.Name -join ', ')
        OutputFile = Split-Path -Leaf $outputPath
        SelectionMode = $selectionMode
        Aggregated = [bool]$AggregateSameSymbolRows
        Rows = $finalRows.Count
    }
}

$summary | Sort-Object SnapshotDate