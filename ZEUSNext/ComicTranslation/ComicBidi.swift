import Foundation

/// Some OCR recognizers emit visual-order Arabic. Convert that model output
/// while preserving Latin words, numbers and their punctuation. This is never
/// applied to translated text: CoreText performs its own shaping and bidi.
enum ComicBidi {
    static func logicalFromVisual(_ text:String)->String{
        let pattern = #"[A-Za-zÀ-ɏ0-9٠-٩۰-۹]+(?:(?:[.,:/]|['-])[A-Za-zÀ-ɏ0-9٠-٩۰-۹]+)*"#
        guard let regex=try? NSRegularExpression(pattern:pattern)else{return text}
        let raw=text as NSString,matches=regex.matches(in:text,range:NSRange(location:0,length:raw.length))
        var runs:[(String,Bool)]=[],end=0
        for match in matches{
            if match.range.location>end{runs.append((raw.substring(with:NSRange(location:end,length:match.range.location-end)),false))}
            let value=raw.substring(with:match.range)
            if runs.count>=2,runs[runs.count-1].0==" ",!runs[runs.count-1].1,runs[runs.count-2].1,
               value.unicodeScalars.contains(where:CharacterSet.letters.contains),runs[runs.count-2].0.unicodeScalars.contains(where:CharacterSet.letters.contains){runs.removeLast();runs[runs.count-1].0+=" "+value}
            else{runs.append((value,true))}
            end=NSMaxRange(match.range)
        }
        if end<raw.length{runs.append((raw.substring(from:end),false))}
        var result=runs.reversed().map{value,protected in protected ? value:String(value.reversed())}.joined()
        // Reversing OCR character order already reverses bracket positions.
        // Mirror only a complete pair whose resulting order is inverted; blindly
        // mirroring every punctuation glyph reverses correctly paired brackets.
        let brackets:[(Character,Character)]=[("(",")"),("[","]"),("{","}"),("<",">"),("«","»")]
        for (open,close) in brackets{
            func balanced(_ value:String)->Bool{var depth=0;for c in value{if c==open{depth+=1};if c==close{depth-=1;if depth<0{return false}}};return depth==0}
            if !balanced(result){let mirrored=String(result.map{$0==open ? close:$0==close ? open:$0});if balanced(mirrored){result=mirrored}}
        }
        return result
    }
}
