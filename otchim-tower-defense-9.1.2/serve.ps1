param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
$gameRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$gameListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 8080)
try {
    $gameListener.Start()
    Write-Host 'Otchim Tower Defense: http://localhost:8080/'
    Write-Host 'Keep this window open. Press Ctrl+C to stop.'
    if (-not $NoBrowser) { Start-Process 'http://localhost:8080/' }
    while ($true) {
        $gameClient = $gameListener.AcceptTcpClient()
        $gameClient.ReceiveTimeout = 3000
        $gameClient.SendTimeout = 3000
        try {
            $gameStream = $gameClient.GetStream()
            $gameReader = [System.IO.StreamReader]::new($gameStream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
            $gameRequestLine = $gameReader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($gameRequestLine)) { continue }
            $gameHeaderCount = 0
            do { $gameHeaderLine = $gameReader.ReadLine(); $gameHeaderCount++ } while ($gameHeaderLine -and $gameHeaderCount -lt 100)
            $gameRequest = $gameRequestLine.Split(' ')
            $gameRelative = [System.Uri]::UnescapeDataString(($gameRequest[1] -split '\?')[0]).TrimStart('/')
            if ([string]::IsNullOrWhiteSpace($gameRelative)) { $gameRelative = 'index.html' }
            $gameTarget = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($gameRoot, $gameRelative))
            $gameAllowed = $gameTarget.StartsWith($gameRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
            $gameStatus = '200 OK'
            $gameMime = 'text/plain; charset=utf-8'
            if ($gameRequest[0] -ne 'GET' -and $gameRequest[0] -ne 'HEAD') {
                $gameStatus = '405 Method Not Allowed'
                $gameBytes = [System.Text.Encoding]::UTF8.GetBytes('Method not allowed')
            } elseif (-not $gameAllowed -or -not [System.IO.File]::Exists($gameTarget)) {
                $gameStatus = '404 Not Found'
                $gameBytes = [System.Text.Encoding]::UTF8.GetBytes('Not found')
            } else {
                $gameMime = switch ([System.IO.Path]::GetExtension($gameTarget)) {
                    '.html' { 'text/html; charset=utf-8' }
                    '.json' { 'application/json; charset=utf-8' }
                    default { 'text/plain; charset=utf-8' }
                }
                $gameBytes = [System.IO.File]::ReadAllBytes($gameTarget)
            }
            $gameResponse = "HTTP/1.1 $gameStatus`r`nContent-Type: $gameMime`r`nContent-Length: $($gameBytes.Length)`r`nConnection: close`r`nX-Content-Type-Options: nosniff`r`n`r`n"
            $gameHeaderBytes = [System.Text.Encoding]::ASCII.GetBytes($gameResponse)
            $gameStream.Write($gameHeaderBytes, 0, $gameHeaderBytes.Length)
            if ($gameRequest[0] -ne 'HEAD') { $gameStream.Write($gameBytes, 0, $gameBytes.Length) }
            $gameStream.Flush()
        } catch {
            # Ignore cancelled requests and idle browser preconnections.
        } finally { $gameClient.Close() }
    }
} catch {
    Write-Host ('Local server error: ' + $_.Exception.Message)
    Write-Host 'Try closing another server on port 8080. For solo play, open index.html directly.'
} finally { $gameListener.Stop() }
