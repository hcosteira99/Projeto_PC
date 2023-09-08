public class Keyboard {
    public char key;
    
    public synchronized char getkey(){
        return this.key;
    }

    public synchronized void setKey(char key){
        this.key=key;
    }

    public synchronized String toString() {
        StringBuilder sb = new StringBuilder();
        sb.append(key);
        return sb.toString();
    }
}
