# Export Word (.docx) -> PDF and PowerPoint (.pptx) -> PDF via Microsoft Office COM
$ErrorActionPreference = "Stop"
$root = "F:\3_DATA_E\4_HocTap\Phan tich phi tuyen ket cau\BaiTapTieuLuan"

$docxPath   = Join-Path $root "ThuyetMinh_PhanTichPhiTuyenHinhHoc_CALFEM.docx"
$wordPdf    = Join-Path $root "ThuyetMinh_PhanTichPhiTuyenHinhHoc_CALFEM.pdf"
$pptxPath   = Join-Path $root "BaoCao_PhanTichPhiTuyenHinhHoc_CALFEM.pptx"
$pptPdf     = Join-Path $root "BaoCao_PhanTichPhiTuyenHinhHoc_CALFEM.pdf"
$tmpWordPdf = Join-Path $env:LOCALAPPDATA "calfem_word_export_tmp.pdf"

Write-Host "[1/2] Exporting Word (.docx) -> PDF via Microsoft Word COM..."
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
$doc = $word.Documents.Open($docxPath, $false, $true)
Write-Host "      Opened Word document ($($doc.ComputeStatistics(2)) pages)."
$doc.ExportAsFixedFormat($tmpWordPdf, 17)
$doc.Close($false)
$word.Quit()
Copy-Item -Path $tmpWordPdf -Destination $wordPdf -Force
Remove-Item -Path $tmpWordPdf -Force -ErrorAction SilentlyContinue
Write-Host "      -> Exported: $wordPdf"

Write-Host "[2/2] Exporting PowerPoint (.pptx) -> PDF via Microsoft PowerPoint COM..."
$ppt = New-Object -ComObject PowerPoint.Application
$pres = $ppt.Presentations.Open($pptxPath, -1, 0, 0)
Write-Host "      Opened PowerPoint deck ($($pres.Slides.Count) slides)."
$pres.SaveAs($pptPdf, 32)
$pres.Close()
$ppt.Quit()
Write-Host "      -> Exported: $pptPdf"
Write-Host "ALL OFFICE PDF EXPORTS COMPLETED!"
