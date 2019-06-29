import { saveAs } from 'file-saver'
import JSZip from 'jszip'

export const exportTxt2Zip = (th: string[], jsonData: any, txtName = 'file', zipName = 'file') => {
  const zip = new JSZip()
  const data = jsonData
  let txtData = `${th}\r\n`
  data.forEach((row: any) => {
    let tempStr = ''
    tempStr = row.toString()
    txtData += `${tempStr}\r\n`
  })
  zip.file(`${txtName}.txt`, txtData)
  zip.generateAsync({
    type: 'blob'
  }).then((blob: Blob) => {
    saveAs(blob, `${zipName}.zip`)
  }, (err: Error) => {
    alert('Zip export failed: ' + err.message)
  })
}
