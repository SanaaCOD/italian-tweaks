namespace PurpleBoost.Models;

public sealed class NavItem
{
    public NavItem(string title, NavPage page)
    {
        Title = title;
        Page = page;
    }

    public string Title { get; }
    public NavPage Page { get; }
}
