import java.io.InputStream;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Properties;

/** Prints the password_secret of each file in a directory as Graylog reads it, in UTF-16 units. */
public class ReadProperties {
  public static void main(String[] args) throws Exception {
    List<Path> files = new ArrayList<>();
    try (DirectoryStream<Path> dir = Files.newDirectoryStream(Path.of(args[0]))) {
      dir.forEach(files::add);
    }
    Collections.sort(files);
    for (Path file : files) {
      System.out.println(file.getFileName() + " " + read(file));
    }
  }

  private static String read(Path file) throws Exception {
    Properties properties = new Properties();
    try (InputStream in = Files.newInputStream(file)) {
      properties.load(in);
    } catch (IllegalArgumentException e) {
      return "malformed";
    }
    String value = properties.getProperty("password_secret");
    if (value == null) {
      return "null";
    }
    StringBuilder units = new StringBuilder();
    for (char c : value.toCharArray()) {
      units.append(String.format("%04x", (int) c));
    }
    return units.toString();
  }
}
