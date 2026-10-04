// Runs cross-engine cases through java.util.regex; see ../cross-engine.ts.
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import java.util.regex.Pattern;
import java.util.regex.PatternSyntaxException;

public class Check {
  static String decode(String field) {
    return new String(Base64.getDecoder().decode(field), StandardCharsets.UTF_8);
  }

  static String search(Pattern regex, String text) {
    return regex.matcher(text).find() ? "1" : "0";
  }

  public static void main(String[] args) throws Exception {
    var lines = Files.readAllLines(Path.of(args[0]), StandardCharsets.UTF_8);
    var meta = Pattern.compile(decode(lines.get(0).split("\t", -1)[1]));
    var output = new StringBuilder();
    for (var line : lines.subList(1, lines.size())) {
      var fields = line.split("\t", -1);
      if (fields[0].equals("V")) {
        output.append(search(meta, decode(fields[1]))).append('\n');
      } else {
        try {
          var regex = Pattern.compile(decode(fields[1]));
          output.append(search(regex, decode(fields[2]))).append('\n');
        } catch (PatternSyntaxException error) {
          output.append("E\n");
        }
      }
    }
    System.out.print(output);
  }
}
