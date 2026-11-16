using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Spreadsheet;
using Microsoft.AspNetCore.Http;
using MAP_WebApp.Models.DB;
using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Xml;

namespace MAP_WebApp.Utils
{
    public static class ExcelUtils
    {

        public static void FillExcel(string filePath, List<usp_GetDataSets> dataSources)
        {
            foreach (var ds in dataSources.OrderBy(e => e.DSIndex))
            {
                DTToExcelTable(filePath, ds.SheetName, GetDataTable(ds));
            }
        }

        public static void FillExcel(MemoryStream filePath, List<usp_GetDataSets> dataSources)
        {
            foreach (var ds in dataSources.OrderBy(e => e.DSIndex))
            {
                DTToExcelTable(filePath, ds.SheetName, GetDataTable(ds));
            }
        }

        public static DataTable ImportExcel(string File, string sheetName, string tableName)
        {
            using (SpreadsheetDocument spredDoc = SpreadsheetDocument.Open(File, false))
                return ExcelTableToDT(spredDoc, sheetName, tableName);
        }

        public static DataTable ImportExcel(IFormFile File, string sheetName, string tableName)
        {
            using (MemoryStream stream = new MemoryStream())
            {
                File.CopyTo(stream);
                return ImportExcel(stream, sheetName, tableName);
            }
        }

        public static DataTable ImportExcel(MemoryStream File, string sheetName, string tableName)
        {
            using (SpreadsheetDocument spredDoc = SpreadsheetDocument.Open(File, true))
                return ExcelTableToDT(spredDoc, sheetName, tableName);
        }

        public static T DBTableSetVal<T>(T DBValue, DataRow Row, string Col)
        {
            var DTField = Row[Col];

            var type = typeof(T);
            Type underType = Nullable.GetUnderlyingType(type);

            if (DTField == DBNull.Value)
            {
                if (DBValue != null)
                    throw new Exception(Col + " cannot be empty!");
                else
                    DBValue = default(T);
            }
            else
            {
                if (underType != null)
                    DBValue = (T)Convert.ChangeType(DTField, underType);
                else
                    DBValue = (T)Convert.ChangeType(DTField, type);
            }

            return DBValue;
        }


        #region export
        private static void DTToExcelTable(string filePath, string sheetName, DataTable dt)
        {
            using (SpreadsheetDocument spreadSheet = SpreadsheetDocument.Open(filePath, true))
            {
                Hyperlinks hyperlinks = new Hyperlinks();
                WorkbookPart workbookPart = spreadSheet.WorkbookPart;
                Sheet sheet = workbookPart.Workbook.Descendants<Sheet>().Where(s => s.Name == sheetName).FirstOrDefault();
                if (sheet == null)
                    return;

                WorksheetPart sheetPart = (WorksheetPart)(workbookPart.GetPartById(sheet.Id));

                if (dt.TableName == "ds_99")
                {
                    for(int i = 0; i < dt.Columns.Count; i++)
                    {
                        Cell cell = sheetPart.Worksheet.Descendants<Cell>().Where(c => c.CellReference == dt.Columns[i].ToString()).FirstOrDefault();
                        cell.CellValue = new CellValue(dt.Rows[0][i].ToString());
                        if (!dt.Rows[0][i].ToString().IsNumeric())
                            cell.DataType = new EnumValue<CellValues>(CellValues.String);
                        else
                            cell.DataType = new EnumValue<CellValues>(CellValues.Number);
                    }
                }
                else
                {
                    var table = sheetPart.TableDefinitionParts.Where(s => s.Table.Name == dt.TableName).FirstOrDefault().Table;
                    if (table == null)
                        return;

                    int firstRowIndex = (int)GetRowIndex(table.Reference.Value.Split(":")[0]);

                    if ((int)GetRowIndex(table.Reference.Value.Split(":")[0]) < (int)GetRowIndex(table.Reference.Value.Split(":")[1]))
                        firstRowIndex += 1;

                    var rowTemplate = InsertRow((uint)firstRowIndex, sheetPart, null);
                    for (int i = firstRowIndex + 1; i < dt.Rows.Count + firstRowIndex; i++)
                        InsertRow((uint)i, sheetPart, rowTemplate);


                    var sheetData = sheetPart.Worksheet.GetFirstChild<SheetData>();
                    var lastCellAddress = CellAddress(firstRowIndex - 1, 1);
                    for (int i = 0; i < dt.Rows.Count; i++)
                    {
                        int rowNo = i + firstRowIndex;
                        for (int a = 0; a < dt.Columns.Count; a++)
                        {
                            lastCellAddress = CellAddress(i + firstRowIndex, a + 1);
                            var row = sheetData.Elements<Row>().Where(r => r.RowIndex == i + firstRowIndex).First();
                            var cell = row.Elements<Cell>().Where(c => c.CellReference.Value == lastCellAddress).First();
                            cell.CellValue = new CellValue(dt.Rows[i][a].ToString());
                            if (!dt.Rows[i][a].ToString().IsNumeric())
                            {
                                if (dt.Rows[i][a].ToString().StartsWith("https://") || dt.Rows[i][a].ToString().StartsWith("http://")) {
                                    Hyperlink hyperlink = new Hyperlink();
                                    hyperlink.Reference = cell.CellReference;
                                    hyperlink.Id = "UNIQUE" + hyperlinks.Count().ToString();
                                    hyperlinks.Append(hyperlink);
                                    sheetPart.AddHyperlinkRelationship(new System.Uri(dt.Rows[i][a].ToString(), System.UriKind.Absolute), true, hyperlink.Id);                                    
                                }
                                cell.DataType = new EnumValue<CellValues>(CellValues.String);
                            }
                            else
                                cell.DataType = new EnumValue<CellValues>(CellValues.Number);
                        }
                    }
                    table.Reference = CellAddress(firstRowIndex - 1, 1) + ":" + lastCellAddress;
                    spreadSheet.WorkbookPart.Workbook.CalculationProperties.ForceFullCalculation = true;
                    spreadSheet.WorkbookPart.Workbook.CalculationProperties.FullCalculationOnLoad = true;
                }

                if (hyperlinks.Count() > 0)
                {
                    PageMargins pageMargins = sheetPart.Worksheet.Descendants<PageMargins>().First();
                    sheetPart.Worksheet.InsertBefore<Hyperlinks>(hyperlinks, pageMargins);
                }
                var props = spreadSheet.PackageProperties;
                props.Creator = "DSM Engines LLC";
                props.LastModifiedBy = "OmniChannel Compliance Tool";
                sheetPart.Worksheet.Save();
                spreadSheet.Save();
            }
        }
        private static void DTToExcelTable(MemoryStream file, string sheetName, DataTable dt)
        {
            using (SpreadsheetDocument spreadSheet = SpreadsheetDocument.Open(file, true))
            {
                Hyperlinks hyperlinks = new Hyperlinks();
                WorkbookPart workbookPart = spreadSheet.WorkbookPart;
                Sheet sheet = workbookPart.Workbook.Descendants<Sheet>().Where(s => s.Name == sheetName).FirstOrDefault();
                if (sheet == null)
                    return;

                WorksheetPart sheetPart = (WorksheetPart)(workbookPart.GetPartById(sheet.Id));

                if (dt.TableName == "ds_99")
                {
                    for (int i = 0; i < dt.Columns.Count; i++)
                    {
                        Cell cell = sheetPart.Worksheet.Descendants<Cell>().Where(c => c.CellReference == dt.Columns[i].ToString()).FirstOrDefault();
                        cell.CellValue = new CellValue(dt.Rows[0][i].ToString());
                        if (!dt.Rows[0][i].ToString().IsNumeric())
                            cell.DataType = new EnumValue<CellValues>(CellValues.String);
                        else
                            cell.DataType = new EnumValue<CellValues>(CellValues.Number);
                    }
                }
                else
                {
                    var table = sheetPart.TableDefinitionParts.Where(s => s.Table.Name == dt.TableName).FirstOrDefault().Table;
                    if (table == null)
                        return;

                    int firstRowIndex = (int)GetRowIndex(table.Reference.Value.Split(":")[0]);

                    if ((int)GetRowIndex(table.Reference.Value.Split(":")[0]) < (int)GetRowIndex(table.Reference.Value.Split(":")[1]))
                        firstRowIndex += 1;

                    var rowTemplate = InsertRow((uint)firstRowIndex, sheetPart, null);
                    for (int i = firstRowIndex + 1; i < dt.Rows.Count + firstRowIndex; i++)
                        InsertRow((uint)i, sheetPart, rowTemplate);


                    var sheetData = sheetPart.Worksheet.GetFirstChild<SheetData>();
                    var lastCellAddress = CellAddress(firstRowIndex - 1, 1);
                    for (int i = 0; i < dt.Rows.Count; i++)
                    {
                        int rowNo = i + firstRowIndex;
                        for (int a = 0; a < dt.Columns.Count; a++)
                        {
                            lastCellAddress = CellAddress(i + firstRowIndex, a + 1);
                            var row = sheetData.Elements<Row>().Where(r => r.RowIndex == i + firstRowIndex).First();
                            var cell = row.Elements<Cell>().Where(c => c.CellReference.Value == lastCellAddress).First();
                            cell.CellValue = new CellValue(dt.Rows[i][a].ToString());
                            if (!dt.Rows[i][a].ToString().IsNumeric())
                            {
                                if (dt.Rows[i][a].ToString().StartsWith("https://") || dt.Rows[i][a].ToString().StartsWith("http://"))
                                {
                                    Hyperlink hyperlink = new Hyperlink();
                                    hyperlink.Reference = cell.CellReference;
                                    hyperlink.Id = "UNIQUE" + hyperlinks.Count().ToString();
                                    hyperlinks.Append(hyperlink);
                                    sheetPart.AddHyperlinkRelationship(new System.Uri(dt.Rows[i][a].ToString(), System.UriKind.Absolute), true, hyperlink.Id);
                                }
                                cell.DataType = new EnumValue<CellValues>(CellValues.String);
                            }
                            else
                                cell.DataType = new EnumValue<CellValues>(CellValues.Number);
                        }
                    }
                    table.Reference = CellAddress(firstRowIndex - 1, 1) + ":" + lastCellAddress;
                    spreadSheet.WorkbookPart.Workbook.CalculationProperties.ForceFullCalculation = true;
                    spreadSheet.WorkbookPart.Workbook.CalculationProperties.FullCalculationOnLoad = true;
                }

                if (hyperlinks.Count() > 0)
                {
                    PageMargins pageMargins = sheetPart.Worksheet.Descendants<PageMargins>().First();
                    sheetPart.Worksheet.InsertBefore<Hyperlinks>(hyperlinks, pageMargins);
                }
                var props = spreadSheet.PackageProperties;
                props.Creator = "DSM Engines MAPQC";
                props.LastModifiedBy = "OmniChannel Compliance Tool";
                sheetPart.Worksheet.Save();
                spreadSheet.Save();
            }
        }
        static string CellAddress(int rowIndex, int colIndex)
        {
            int div = colIndex;
            string colLetter = String.Empty;
            int mod = 0;

            while (div > 0)
            {
                mod = (div - 1) % 26;
                colLetter = (char)(65 + mod) + colLetter;
                div = (int)((div - mod) / 26);
            }
            return colLetter + rowIndex.ToString();
        }
        public static bool IsNumeric(this string text)
        {
            return double.TryParse(text, out double test);
        }
        #region export
        private static string GetColumnName(string cellName)
        {
            // Create a regular expression to match the column name portion of the cell name.
            Regex regex = new Regex("[A-Za-z]+");
            Match match = regex.Match(cellName);

            return match.Value;
        }
        public enum CellReferencePartEnum
        {
            None,
            Column,
            Row,
            Both
        }
        private static List<char> Letters = new List<char>() { 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', ' ' };

        public static Row InsertRow(uint rowIndex, WorksheetPart worksheetPart, Row insertRow, bool isNewLastRow = false)
        {
            Worksheet worksheet = worksheetPart.Worksheet;
            SheetData sheetData = worksheet.GetFirstChild<SheetData>();

            Row retRow = !isNewLastRow ? sheetData.Elements<Row>().FirstOrDefault(r => r.RowIndex == rowIndex) : null;

            // If the worksheet does not contain a row with the specified row index, insert one.
            if (retRow != null)
            {
                // if retRow is not null and we are inserting a new row, then move all existing rows down.
                if (insertRow != null)
                {
                    UpdateRowIndexes(worksheetPart, rowIndex, false);
                    UpdateMergedCellReferences(worksheetPart, rowIndex, false);
                    UpdateHyperlinkReferences(worksheetPart, rowIndex, false);

                    // actually insert the new row into the sheet
                    retRow = sheetData.InsertBefore(insertRow, retRow);  // at this point, retRow still points to the row that had the insert rowIndex

                    string curIndex = retRow.RowIndex.ToString();
                    string newIndex = rowIndex.ToString();

                    foreach (Cell cell in retRow.Elements<Cell>())
                    {
                        // Update the references for the rows cells.
                        cell.CellReference = new StringValue(cell.CellReference.Value.Replace(curIndex, newIndex));
                    }

                    // Update the row index.
                    retRow.RowIndex = rowIndex;
                }
            }
            else
            {
                // Row doesn't exist yet, shifting not needed.
                // Rows must be in sequential order according to RowIndex. Determine where to insert the new row.
                Row refRow = !isNewLastRow ? sheetData.Elements<Row>().FirstOrDefault(row => row.RowIndex > rowIndex) : null;

                // use the insert row if it exists
                retRow = new Row() { RowIndex = rowIndex };
                if (insertRow != null)
                    retRow = (Row)insertRow.CloneNode(true);

                IEnumerable<Cell> cellsInRow = retRow.Elements<Cell>();

                if (cellsInRow.Any())
                {
                    string curIndex = retRow.RowIndex.ToString();
                    string newIndex = rowIndex.ToString();

                    foreach (Cell cell in cellsInRow)
                    {
                        // Update the references for the rows cells.
                        cell.CellReference = new StringValue(cell.CellReference.Value.Replace(curIndex, newIndex));
                    }

                    // Update the row index.
                    retRow.RowIndex = rowIndex;
                }

                sheetData.InsertBefore(retRow, refRow);
            }

            return retRow;
        }
        private static void UpdateRowIndexes(WorksheetPart worksheetPart, uint rowIndex, bool isDeletedRow)
        {
            // Get all the rows in the worksheet with equal or higher row index values than the one being inserted/deleted for reindexing.
            IEnumerable<Row> rows = worksheetPart.Worksheet.Descendants<Row>().Where(r => r.RowIndex.Value >= rowIndex);

            foreach (Row row in rows)
            {
                uint newIndex = (isDeletedRow ? row.RowIndex - 1 : row.RowIndex + 1);
                string curRowIndex = row.RowIndex.ToString();
                string newRowIndex = newIndex.ToString();

                foreach (Cell cell in row.Elements<Cell>())
                {
                    // Update the references for the rows cells.
                    cell.CellReference = new StringValue(cell.CellReference.Value.Replace(curRowIndex, newRowIndex));
                }

                // Update the row index.
                row.RowIndex = newIndex;
            }
        }
        /// <summary>
        /// Updates the MergedCelss reference whenever a new row is inserted or deleted. It will simply take the
        /// row index and either increment or decrement the cell row index in the merged cell reference based on
        /// if the row was inserted or deleted.
        /// </summary>
        /// <param name="worksheetPart">Worksheet Part</param>
        /// <param name="rowIndex">Row Index being inserted or deleted</param>
        /// <param name="isDeletedRow">True if row was deleted, otherwise false</param>
        private static void UpdateMergedCellReferences(WorksheetPart worksheetPart, uint rowIndex, bool isDeletedRow)
        {
            if (worksheetPart.Worksheet.Elements<MergeCells>().Count() > 0)
            {
                MergeCells mergeCells = worksheetPart.Worksheet.Elements<MergeCells>().FirstOrDefault();

                if (mergeCells != null)
                {
                    // Grab all the merged cells that have a merge cell row index reference equal to or greater than the row index passed in
                    List<MergeCell> mergeCellsList = mergeCells.Elements<MergeCell>().Where(r => r.Reference.HasValue)
                                                                                     .Where(r => GetRowIndex(r.Reference.Value.Split(':').ElementAt(0)) >= rowIndex ||
                                                                                                 GetRowIndex(r.Reference.Value.Split(':').ElementAt(1)) >= rowIndex).ToList();

                    // Need to remove all merged cells that have a matching rowIndex when the row is deleted
                    if (isDeletedRow)
                    {
                        List<MergeCell> mergeCellsToDelete = mergeCellsList.Where(r => GetRowIndex(r.Reference.Value.Split(':').ElementAt(0)) == rowIndex ||
                                                                                       GetRowIndex(r.Reference.Value.Split(':').ElementAt(1)) == rowIndex).ToList();

                        // Delete all the matching merged cells
                        foreach (MergeCell cellToDelete in mergeCellsToDelete)
                        {
                            cellToDelete.Remove();
                        }

                        // Update the list to contain all merged cells greater than the deleted row index
                        mergeCellsList = mergeCells.Elements<MergeCell>().Where(r => r.Reference.HasValue)
                                                                         .Where(r => GetRowIndex(r.Reference.Value.Split(':').ElementAt(0)) > rowIndex ||
                                                                                     GetRowIndex(r.Reference.Value.Split(':').ElementAt(1)) > rowIndex).ToList();
                    }

                    // Either increment or decrement the row index on the merged cell reference
                    foreach (MergeCell mergeCell in mergeCellsList)
                    {
                        string[] cellReference = mergeCell.Reference.Value.Split(':');

                        if (GetRowIndex(cellReference.ElementAt(0)) >= rowIndex)
                        {
                            string columnName = GetColumnName(cellReference.ElementAt(0));
                            cellReference[0] = isDeletedRow ? columnName + (GetRowIndex(cellReference.ElementAt(0)) - 1).ToString() : IncrementCellReference(cellReference.ElementAt(0), CellReferencePartEnum.Row);
                        }

                        if (GetRowIndex(cellReference.ElementAt(1)) >= rowIndex)
                        {
                            string columnName = GetColumnName(cellReference.ElementAt(1));
                            cellReference[1] = isDeletedRow ? columnName + (GetRowIndex(cellReference.ElementAt(1)) - 1).ToString() : IncrementCellReference(cellReference.ElementAt(1), CellReferencePartEnum.Row);
                        }

                        mergeCell.Reference = new StringValue(cellReference[0] + ":" + cellReference[1]);
                    }
                }
            }
        }

        /// <summary>
        /// Updates all hyperlinks in the worksheet when a row is inserted or deleted.
        /// </summary>
        /// <param name="worksheetPart">Worksheet Part</param>
        /// <param name="rowIndex">Row Index being inserted or deleted</param>
        /// <param name="isDeletedRow">True if row was deleted, otherwise false</param>
        private static void UpdateHyperlinkReferences(WorksheetPart worksheetPart, uint rowIndex, bool isDeletedRow)
        {
            Hyperlinks hyperlinks = worksheetPart.Worksheet.Elements<Hyperlinks>().FirstOrDefault();

            if (hyperlinks != null)
            {
                Match hyperlinkRowIndexMatch;
                uint hyperlinkRowIndex;

                foreach (Hyperlink hyperlink in hyperlinks.Elements<Hyperlink>())
                {
                    hyperlinkRowIndexMatch = Regex.Match(hyperlink.Reference.Value, "[0-9]+");
                    if (hyperlinkRowIndexMatch.Success && uint.TryParse(hyperlinkRowIndexMatch.Value, out hyperlinkRowIndex) && hyperlinkRowIndex >= rowIndex)
                    {
                        // if being deleted, hyperlink needs to be removed or moved up
                        if (isDeletedRow)
                        {
                            // if hyperlink is on the row being removed, remove it
                            if (hyperlinkRowIndex == rowIndex)
                            {
                                hyperlink.Remove();
                            }
                            // else hyperlink needs to be moved up a row
                            else
                            {
                                hyperlink.Reference.Value = hyperlink.Reference.Value.Replace(hyperlinkRowIndexMatch.Value, (hyperlinkRowIndex - 1).ToString());

                            }
                        }
                        // else row is being inserted, move hyperlink down
                        else
                        {
                            hyperlink.Reference.Value = hyperlink.Reference.Value.Replace(hyperlinkRowIndexMatch.Value, (hyperlinkRowIndex + 1).ToString());
                        }
                    }
                }

                // Remove the hyperlinks collection if none remain
                if (hyperlinks.Elements<Hyperlink>().Count() == 0)
                {
                    hyperlinks.Remove();
                }
            }
        }

        /// <summary>
        /// Given a cell name, parses the specified cell to get the row index.
        /// </summary>
        /// <param name="cellReference">Address of the cell (ie. B2)</param>
        /// <returns>Row Index (ie. 2)</returns>
        public static uint GetRowIndex(string cellReference)
        {
            // Create a regular expression to match the row index portion the cell name.
            Regex regex = new Regex(@"\d+");
            Match match = regex.Match(cellReference);

            return uint.Parse(match.Value);
        }

        /// <summary>
        /// Increments the reference of a given cell.  This reference comes from the CellReference property
        /// on a Cell.
        /// </summary>
        /// <param name="reference">reference string</param>
        /// <param name="cellRefPart">indicates what is to be incremented</param>
        /// <returns></returns>
        public static string IncrementCellReference(string reference, CellReferencePartEnum cellRefPart)
        {
            string newReference = reference;

            if (cellRefPart != CellReferencePartEnum.None && !String.IsNullOrEmpty(reference))
            {
                string[] parts = Regex.Split(reference, "([A-Z]+)");

                if (cellRefPart == CellReferencePartEnum.Column || cellRefPart == CellReferencePartEnum.Both)
                {
                    List<char> col = parts[1].ToCharArray().ToList();
                    bool needsIncrement = true;
                    int index = col.Count - 1;

                    do
                    {
                        // increment the last letter
                        col[index] = Letters[Letters.IndexOf(col[index]) + 1];

                        // if it is the last letter, then we need to roll it over to 'A'
                        if (col[index] == Letters[Letters.Count - 1])
                        {
                            col[index] = Letters[0];
                        }
                        else
                        {
                            needsIncrement = false;
                        }

                    } while (needsIncrement && --index >= 0);

                    // If true, then we need to add another letter to the mix. Initial value was something like "ZZ"
                    if (needsIncrement)
                    {
                        col.Add(Letters[0]);
                    }

                    parts[1] = new String(col.ToArray());
                }

                if (cellRefPart == CellReferencePartEnum.Row || cellRefPart == CellReferencePartEnum.Both)
                {
                    // Increment the row number. A reference is invalid without this componenet, so we assume it will always be present.
                    parts[2] = (int.Parse(parts[2]) + 1).ToString();
                }

                newReference = parts[1] + parts[2];
            }

            return newReference;
        }
        #endregion
        private static System.Data.DataTable GetDataTable(usp_GetDataSets dataSet)
        {
            XmlDocument xmlDocument = new XmlDocument();
            xmlDocument.LoadXml(dataSet.Data);
            DataSet dstaSet = new DataSet();
            dstaSet.ReadXml(new XmlNodeReader(xmlDocument));
            var result = dstaSet.Tables[0];
            result.TableName = "ds_" + dataSet.DSIndex.ToString();
            return result;
        }
        #endregion

        #region Import
        private static DataTable ExcelTableToDT(SpreadsheetDocument spredDoc, string sheetName, string tableName)
        {
            DataTable dataTable = new DataTable();


            Workbook workbook = spredDoc.WorkbookPart.Workbook;
            Sheet sheet = workbook.Descendants<Sheet>().FirstOrDefault(s => s.Name == sheetName);
            if (sheet == null)
                return null;

            SharedStringTable sharedStringTable = workbook.WorkbookPart.SharedStringTablePart.SharedStringTable;
            List<SharedStringItem> sharedStringItems = sharedStringTable.Descendants<SharedStringItem>().ToList<SharedStringItem>();
            WorksheetPart sheetPart = (WorksheetPart)spredDoc.WorkbookPart.GetPartById(sheet.Id);
            TableDefinitionPart table = sheetPart.TableDefinitionParts.FirstOrDefault(s => s.Table.Name == tableName);
            if (table == null)
                return null;

            Table excelTable = table.Table;
            int colcounter = 0;
            foreach (TableColumn col in excelTable.TableColumns)
            {
                DataColumn dcol = dataTable.Columns.Add(col.Name);
                dcol.SetOrdinal(colcounter);
                colcounter++;
            }

            SheetData data = sheetPart.Worksheet.Elements<SheetData>().First();

            foreach (Row row in data)
            {
                if (isInTable(row.Descendants<Cell>().FirstOrDefault(), excelTable.Reference, true))
                {
                    int cellcount = 0;
                    DataRow dataRow = dataTable.NewRow();
                    foreach (Cell cell in row.Elements<Cell>())
                    {
                        if (cell.CellValue == null)
                            dataRow[cellcount] = null;
                        else
                        {
                            if (cell.DataType != null && cell.DataType.InnerText == "s")
                            {
                                dataRow[cellcount] = sharedStringItems[int.Parse(cell.CellValue.InnerText)].InnerText;
                            }
                            else if (cell.DataType != null && cell.DataType.InnerText == "str")
                            {
                                dataRow[cellcount] = cell.CellValue.InnerText;
                            }
                            else
                            {
                                dataRow[cellcount] = Decimal.Parse(cell.CellValue.Text, NumberStyles.AllowExponent | NumberStyles.AllowDecimalPoint | NumberStyles.AllowLeadingSign);
                            }
                        }
                        cellcount++;
                    }
                    dataTable.Rows.Add(dataRow);
                }
            }

            return dataTable;
        }
        private static Tuple<int, int> returnCellReference(string cellRef)
        {
            int startIndex = cellRef.IndexOfAny("0123456789".ToCharArray());
            string column = cellRef.Substring(0, startIndex);
            int row = Int32.Parse(cellRef.Substring(startIndex));
            return new Tuple<int, int>(TextToNumber(column), row);
        }
        private static int TextToNumber(string text)
        {
            return text
                .Select(c => c - 'A' + 1)
                .Aggregate((sum, next) => sum * 26 + next);
        }
        private static bool isInTable(Cell testCell, string tableRef, bool headerRow)
        {
            Tuple<int, int> cellRef = returnCellReference(testCell.CellReference.ToString());
            if (tableRef.Contains(":"))
            {
                int header = 0;
                if (headerRow)
                {
                    header = 1;
                }
                string[] tableExtremes = tableRef.Split(':');
                Tuple<int, int> startCell = returnCellReference(tableExtremes[0]);
                Tuple<int, int> endCell = returnCellReference(tableExtremes[1]);
                if (cellRef.Item1 >= startCell.Item1
                    && cellRef.Item1 <= endCell.Item1
                    && cellRef.Item2 >= startCell.Item2 + header
                    && cellRef.Item2 <= endCell.Item2) { return true; }
                else { return false; }
            }
            else if (cellRef.Equals(returnCellReference(tableRef)))
            {
                return true;
            }
            else
            {
                return false;
            }
        }
        #endregion
    }
}