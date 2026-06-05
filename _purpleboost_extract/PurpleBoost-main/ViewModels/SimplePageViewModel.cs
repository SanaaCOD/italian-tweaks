using System.Collections.ObjectModel;
using PurpleBoost.Models;

namespace PurpleBoost.ViewModels;

public sealed class InfoCard
{
    public InfoCard(string title, string description)
    {
        Title = title;
        Description = description;
    }

    public string Title { get; }
    public string Description { get; }
}

public sealed class SimplePageViewModel : BaseViewModel
{
    public SimplePageViewModel(string title, string subtitle, IEnumerable<InfoCard> cards)
    {
        Title = title;
        Subtitle = subtitle;
        foreach (var c in cards)
            Cards.Add(c);
    }

    public string Title { get; }
    public string Subtitle { get; }
    public ObservableCollection<InfoCard> Cards { get; } = new();

    public static SimplePageViewModel Peripheral() =>
        new(
            "Périphérique",
            "Optimisation manette, souris, clavier et USB — scripts PowerShell à brancher plus tard.",
            new[]
            {
                new InfoCard("Manette", "Latence / profils (à venir)"),
                new InfoCard("Souris", "Polling / raw input (à venir)"),
                new InfoCard("Clavier", "Anti-ghosting / debounce (à venir)"),
                new InfoCard("USB", "Hubs / contrôleurs (à venir)"),
            });

    public static SimplePageViewModel Drivers() =>
        new(
            "Drivers",
            "Pilotes GPU, chipset et audio — liens officiels et vérifications (à venir).",
            new[]
            {
                new InfoCard("NVIDIA", "Détection + liens (à venir)"),
                new InfoCard("AMD", "Détection + liens (à venir)"),
                new InfoCard("Chipset", "À venir"),
                new InfoCard("Audio", "À venir"),
            });

    public static SimplePageViewModel Connection() =>
        new(
            "Connexion",
            "DNS, TCP, ping et profils réseau orientés latence (à venir).",
            new[]
            {
                new InfoCard("DNS", "Presets + rollback (à venir)"),
                new InfoCard("TCP Optimizer", "Scripts validés (à venir)"),
                new InfoCard("Ping", "Mesure simple (à venir)"),
                new InfoCard("Latence réseau", "Diagnostics (à venir)"),
            });

    public static SimplePageViewModel Game() =>
        new(
            "Jeu",
            "Profils par titre — aucune modification automatique sans confirmation.",
            new[]
            {
                new InfoCard("Warzone", "Profil (à venir)"),
                new InfoCard("Fortnite", "Profil (à venir)"),
                new InfoCard("Apex", "Profil (à venir)"),
                new InfoCard("Profils personnalisés", "À venir"),
            });

    public static SimplePageViewModel Sound() =>
        new(
            "Son",
            "Audio Windows, VoiceMeeter, Discord — presets (à venir).",
            new[]
            {
                new InfoCard("VoiceMeeter", "Presets (à venir)"),
                new InfoCard("Périphérique audio", "Sortie / formats (à venir)"),
                new InfoCard("Discord", "Réglages (à venir)"),
                new InfoCard("Optimisation Warzone audio", "À venir"),
            });
}
