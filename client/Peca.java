import java.util.Objects;

public class Peca {
    public float x;
    public float y;
    public String username;
    public int r = 0;
    public int g = 0;
    public int b = 0;
    public float angle;
    public int wins;
    public boolean isPlayer;



    public Peca(String username, String color, float x, float y, float angle,int wins){
        this.username = username;
        setColor(color);
        this.x = x;
        this.y = y;
        this.angle = angle;
        this.wins=wins;
        this.isPlayer = !username.equals("<>");
    }

    void setColor(String color){

        if(color.equals("blue"))
            this.b = 255;
        else if (color.equals("red"))
            this.r = 255;
        else
            this.g  = 255;

    }
}
