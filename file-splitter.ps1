<#
.SYNOPSIS
    Splits a large file into smaller binary chunks, converts each chunk to Base64,
    and saves them as text files.

.DESCRIPTION
    This function reads a large file, splits it into chunks, and saves each chunk
    as a Base64-encoded string in a .txt file.

.PARAMETER FilePath
    The full path to the large file you want to split (e.g., the .zip file).

.PARAMETER ChunkSizeInMB
    The maximum size (in Megabytes) for each *binary* chunk *before* Base64 encoding.
    Note: The resulting .txt files will be ~33% larger.

.EXAMPLE
    Split-BinaryTo-Base64-Text -FilePath "C:\temp\my-archive.zip" -ChunkSizeInMB 20
    This will create files like "my-archive.zip.part001.txt".
#>
function Split-BinaryTo-Base64-Text {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [int]$ChunkSizeInMB
    )

    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        Write-Error "Error: File not found at '$FilePath'"
        return
    }

    $chunkSizeInBytes = $ChunkSizeInMB * 1024 * 1024
    $buffer = New-Object byte[] $chunkSizeInBytes
    $partNumber = 1
    
    # Use a FileStream to read the file in chunks
    try {
        $fileStream = [System.IO.File]::OpenRead($FilePath)
        Write-Host "Splitting '$FilePath' into ${ChunkSizeInMB}MB chunks and encoding to Base64..."
        
        while (($bytesRead = $fileStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $chunkFileName = "{0}.part{1:D3}.txt" -f $FilePath, $partNumber
            Write-Host "Creating text chunk: $chunkFileName"

            # Ensure we only convert the bytes actually read
            $bytesToWrite = $buffer
            if ($bytesRead -lt $buffer.Length) {
                $bytesToWrite = $buffer[0..($bytesRead - 1)]
            }
            
            # Convert the binary chunk to a Base64 string
            $base64String = [System.Convert]::ToBase64String($bytesToWrite)
            
            # Save the Base64 string to the text file
            Set-Content -Path $chunkFileName -Value $base64String -Encoding Ascii
            
            $partNumber++
        }
    }
    catch {
        Write-Error "An error occurred during splitting and encoding: $_"
    }
    finally {
        if ($fileStream) {
            $fileStream.Close()
        }
    }
    
    Write-Host "File splitting complete. $($partNumber - 1) text chunks created."
}

<#
.SYNOPSIS
    Joins Base64-encoded text chunks back into a single binary file.

.DESCRIPTION
    This function finds all text parts (e.g., .part001.txt), reads the Base64 string
    from each, decodes it back to binary, and combines them to recreate the original file.

.PARAMETER BaseFilePath
    The path and base name of the original file (e.g., "C:\temp\my-archive.zip").
    The function will look for chunk files matching "my-archive.zip.part*.txt".

.EXAMPLE
    Join-Base64-TextTo-Binary -BaseFilePath "C:\temp\my-archive.zip"
    This will find all ".part*.txt" files and join them back into "C:\temp\my-archive.zip".
    The original chunk files will be deleted after successful re-composition.
#>
function Join-Base64-TextTo-Binary {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseFilePath
    )

    $chunkFilePattern = "$BaseFilePath.part*.txt"
    $chunkFiles = Get-ChildItem -Path $chunkFilePattern | Sort-Object Name
    
    if ($chunkFiles.Count -eq 0) {
        Write-Error "Error: No text chunk files found matching '$chunkFilePattern'"
        return
    }

    Write-Host "Found $($chunkFiles.Count) text chunks. Starting re-composition..."

    # Create or overwrite the output file
    try {
        $outputStream = [System.IO.File]::OpenWrite($BaseFilePath)
        
        foreach ($chunkFile in $chunkFiles) {
            Write-Host "Reading and decoding chunk: $($chunkFile.Name)"
            
            # Read the Base64 string from the text file
            $base64String = Get-Content -Path $chunkFile.FullName -Raw
            
            # Convert the Base64 string back to a byte array
            $chunkBytes = [System.Convert]::FromBase64String($base64String)
            
            # Write the decoded bytes to the output file
            $outputStream.Write($chunkBytes, 0, $chunkBytes.Length)
        }
        
        Write-Host "Re-composition complete. Output file: $BaseFilePath"
    }
    catch {
        Write-Error "An error occurred during joining and decoding: $_"
    }
    finally {
        if ($outputStream) {
            $outputStream.Close()
        }
    }

    # Optional: Clean up chunk files after successful join
    try {
        Write-Host "Cleaning up text chunk files..."
        foreach ($chunkFile in $chunkFiles) {
            Remove-Item $chunkFile.FullName
        }
        Write-Host "Cleanup complete."
    }
    catch {
        Write-Warning "Could not clean up chunk files: $_"
    }
}

# --- Wrapper functions (These are what you will call) ---

<#
.SYNOPSIS
    Compresses an executable (or any file) into a ZIP archive, then splits that archive 
    into Base64-encoded text chunks.

.DESCRIPTION
    This function automates the flow: EXE -> ZIP -> Base64-TXT-CHUNKS.
    It uses Compress-Archive, then calls Split-BinaryTo-Base64-Text.
    The intermediate .zip file is deleted after splitting.

.PARAMETER ExecutableFilePath
    The full path to the executable (or any file) you want to compress and split.

.PARAMETER ChunkSizeInMB
    The maximum size (in Megabytes) for each binary chunk *before* encoding.

.EXAMPLE
    Compress-And-Split-To-Text -ExecutableFilePath "C:\temp\my-program.exe" -ChunkSizeInMB 20
#>
function Compress-And-Split-To-Text {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ExecutableFilePath,

        [Parameter(Mandatory = $true)]
        [int]$ChunkSizeInMB
    )

    if (-not (Test-Path -Path $ExecutableFilePath -PathType Leaf)) {
        Write-Error "Error: File not found at '$ExecutableFilePath'"
        return
    }

    $zipFilePath = "$ExecutableFilePath.zip"

    try {
        Write-Host "Compressing '$ExecutableFilePath' to '$zipFilePath'..."
        Compress-Archive -Path $ExecutableFilePath -DestinationPath $zipFilePath -ErrorAction Stop
        
        Write-Host "Compression complete. Now splitting '$zipFilePath' to text chunks..."
        Split-BinaryTo-Base64-Text -FilePath $zipFilePath -ChunkSizeInMB $ChunkSizeInMB
        
        Write-Host "Splitting complete. Cleaning up intermediate zip file..."
        Remove-Item $zipFilePath
        
        Write-Host "Process complete. Text chunks are ready."
    }
    catch {
        Write-Error "An error occurred during compression or splitting: $_"
        if (Test-Path -Path $zipFilePath -PathType Leaf) {
            Write-Warning "Intermediate file '$zipFilePath' might still exist."
        }
    }
}


<#
.SYNOPSIS
    Joins Base64-encoded text chunks back into a ZIP archive, then uncompresses it.

.DESCRIPTION
    This function automates the flow: Base64-TXT-CHUNKS -> REASSEMBLE (ZIP) -> UNZIP (EXE).
    It calls Join-Base64-TextTo-Binary to recreate the .zip file, then expands it.
    The reassembled .zip file and text chunks are deleted after extraction.

.PARAMETER OriginalExecutablePath
    The full path to the *original* file (e.g., "C:\temp\my-program.exe").
    This is used to find the chunk files (e.g., "C:\temp\my-program.exe.zip.part*.txt")
    and to know where to extract the file.

.EXAMPLE
    Join-And-Uncompress-From-Text -OriginalExecutablePath "C:\temp\my-program.exe"
#>
function Join-And-Uncompress-From-Text {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$OriginalExecutablePath
    )

    $zipFilePath = "$OriginalExecutablePath.zip"
    $destinationFolder = Split-Path -Path $OriginalExecutablePath -Parent

    if ([string]::IsNullOrEmpty($destinationFolder)) {
        $destinationFolder = ".\"
    }

    try {
        Write-Host "Joining text chunks to recreate '$zipFilePath'..."
        Join-Base64-TextTo-Binary -BaseFilePath $zipFilePath
        
        if (-not (Test-Path -Path $zipFilePath -PathType Leaf)) {
            Write-Error "Error: Joining files failed. '$zipFilePath' was not created."
            return
        }

        Write-Host "Join complete. Expanding archive to '$destinationFolder'..."
        Expand-Archive -Path $zipFilePath -DestinationPath $destinationFolder -Force -ErrorAction Stop
        
        Write-Host "Expansion complete. Cleaning up intermediate zip file..."
        Remove-Item $zipFilePath
        
        Write-Host "Process complete. Original file '$OriginalExecutablePath' has been restored."
    }
    catch {
        Write-Error "An error occurred during joining or uncompessing: $_"
        if (Test-Path -Path $zipFilePath -PathType Leaf) {
            Write-Warning "Intermediate file '$zipFilePath' might still exist."
        }
    }
}


# --- EXAMPLE USAGE (HOW TO USE THIS SCRIPT) ---
#
# **FIRST: LOAD THE SCRIPT IN POWERSHELL**
#    1. Save this file as "split_join_files.ps1".
#    2. Open PowerShell and 'cd' to where you saved it (e.g., cd C:\my-scripts).
#    3. Load the script:
#       . .\split_join_files.ps1
#    * (If you get an error, run this first: Unblock-File -Path .\split_join_files.ps1)
#
# -----------------------------------------------------------------
#
# **HOW TO SPLIT (EXE -> TXT Chunks)**
#
#    Run 'Compress-And-Split-To-Text'.
#    (This takes your .exe, zips it, and creates the .txt chunks.)
#
#    Compress-And-Split-To-Text -ExecutableFilePath "C:\my-files\my-game.exe" -ChunkSizeInMB 20
#
#    - WHAT HAPPENS:
#      - It creates text files: "my-game.exe.zip.part001.txt", "my-game.exe.zip.part002.txt", etc.
#
# -----------------------------------------------------------------
#
# **HOW TO REASSEMBLE (TXT Chunks -> ZIP)**
#    (This takes your .txt chunks and turns them back into the .zip file.)
#
#    Run 'Join-Base64-TextTo-Binary'.
#    You must give it the *full zip file name* you want to create.
#
#    Join-Base64-TextTo-Binary -BaseFilePath "C:\my-files\my-game.exe.zip"
#
#    - WHAT HAPPWEBS:
#      - It finds all "my-game.exe.zip.part*.txt" files and joins them.
#      - It creates "C:\my-files\my-game.exe.zip".
#      - You can now unzip this file manually.
#
# -----------------------------------------------------------------
#
# **ALTERNATIVE: REASSEMBLE (TXT Chunks -> Original EXE)**
#    (This does everything: joins the chunks AND unzips the file for you.)
#
#    Run 'Join-And-Uncompress-From-Text'.
#    You must give it the *original .exe file path*.
#
#    Join-And-Uncompress-From-Text -OriginalExecutablePath "C:\my-files\my-game.exe"
#
#    - WHAT HAPPENS:
#      - It joins the chunks to a .zip, unzips it, and deletes all temp files.
#      - It restores "C:\my-files\my-game.exe".
#


