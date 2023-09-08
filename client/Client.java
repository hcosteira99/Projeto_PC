import java.util.List;
import java.util.Set;

public class Client {
    public static void main(String[] args) {
        try {
            if ( args.length < 2) {
                print("Incorrect syntax:");
                print("java client [host] [port] ");
                System.exit(1);
            }

            ConnectionManager CC = new ConnectionManager(args[0], Integer.parseInt(args[1]));
            Keyboard keyboard= new Keyboard();
            Mouse mouse = new Mouse();
            Espaco espaco = new Espaco();
            Data data = new Data();

            new Thread(new Screen(mouse,keyboard, espaco, data)).start();

            new Thread(new Handler(CC,keyboard,espaco, data)).start();


            
        } catch (Exception e) {
            print(e.getMessage());
        }
    }

    public static void print(String message) {
        System.out.println(message);
    }
}