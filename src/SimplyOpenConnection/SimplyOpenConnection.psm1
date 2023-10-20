using namespace System.Management.Automation

#Requires -Modules SimplySql

$RequestFunctionTemplate = @'
function [[FUNCTION_NAME]] {
    [[CMDLET_BINDING]]
    param(
    [[PARAM_BLOCK]]

    )

    $ConnectionNameSplat = @{}
    if ( $PSBoundParameters.ContainsKey('ConnectionName') ) {
        $ConnectionNameSplat.ConnectionName = $ConnectionName
    }

    for ( $i = 0; $i -lt 5; $i ++ ) {

        Write-Verbose ( 'Connection attempt {0} of 5...' -f ( $i + 1 ) )

        $SqlConnection = Get-SqlConnection @ConnectionNameSplat -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

        # if there is no active connection we create one
        if ( $null -eq $SqlConnection ) {
            Write-Verbose 'Calling [[COMMAND]] to establish connection...'
            [[COMMAND]] @PSBoundParameters
            $SqlConnection = Get-SqlConnection @ConnectionNameSplat -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        }

        switch ( [int]$SqlConnection.State ) {

            # Closed
            0 {
                Write-Verbose 'Connection Status: Closed'
                Close-SqlConnection
            }

            # Open
            1 {
                if ( Test-SqlConnection ) {
                    Write-Verbose 'Connection Status: Open'    
                    return $SqlConnection
                } else {
                    Write-Verbose 'Connection Status: Failed'    
                    Close-SqlConnection
                }
            }

            # Connecting
            2 {
                Write-Verbose 'Connection Status: Connecting'
                Start-Sleep -Milliseconds 50
            }

            # Executing (another query)
            4 {
                Write-Verbose 'Connection Status: Executing'
                Start-Sleep -Milliseconds 100
            }

            # Fetching (results of another query)
            8 {
                Write-Verbose 'Connection Status: Fetching'
                Start-Sleep -Milliseconds 100
            }

            # Broken
            16 {
                Write-Verbose 'Connection Status: Broken'
                Close-SqlConnection
            }

        }

    }

}
'@

Get-Command -Module SimplySql -Name Open-* | ForEach-Object {
    $CommandMetadata = [CommandMetadata]::new($_)
    $FunctionName = 'Request-{0}' -f $CommandMetadata.Name.Replace('-','')
    $ProxyCommand = $RequestFunctionTemplate.
        Replace('[[FUNCTION_NAME]]', $FunctionName).
        Replace('[[CMDLET_BINDING]]', [ProxyCommand]::GetCmdletBindingAttribute($CommandMetadata)).
        Replace('[[PARAM_BLOCK]]', [ProxyCommand]::GetParamBlock($CommandMetadata)).
        Replace('[[COMMAND]]', $_.Name)
    . ([scriptblock]::Create($ProxyCommand))
}

