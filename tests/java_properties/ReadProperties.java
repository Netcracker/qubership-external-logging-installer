import java.io.InputStream;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Properties;

/** Prints the password_secret of each file in a directory as Graylog reads it, in UTF-16 code units. */
public class ReadProperties {
    public static void main(String[] args) throws Exception {
        List<Path> files = new ArrayList<>();
        try (DirectoryStream<Path> dir = Files.newDirectoryStream(Path.of(args[0]))) {
            dir.forEach(files::add);
        }
        Collections.sort(files);
        for (Path file : files) {
            Properties properties = new Properties();
            String value;
            try (InputStream in = Files.newInputStream(file)) {
                properties.load(in);
                value = properties.getProperty("password_secret");
            } catch (IllegalArgumentException e) {
                value = null;
                System.out.println(file.getFileName() + " malformed");
                continue;
            }
            StringBuilder units = new StringBuilder();
            if (value == null) {
                units.append("null");
            }
            for (char c : value == null ? new char[0] : value.toCharArray()) {
                units.append(String.format("%04x", (int) c));
            }
            System.out.println(file.getFileName() + " " + units);
        }
    }
}
