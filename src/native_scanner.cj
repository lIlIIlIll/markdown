package markdown

foreign func MD_Markdown_ScanLines(input: CPointer<UInt8>, length: Int64, records: CPointer<UInt64>, capacity: Int64): Int64
