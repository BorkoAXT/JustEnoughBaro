#nullable enable

using System;
using System.Collections.Generic;
using System.Linq;
using Barotrauma;
using Microsoft.Xna.Framework;

namespace JustEnoughBaro;

/// <summary>
/// Browser shell shared by every prefab family. The index and metadata panes are data-driven;
/// prefab-specific presentation lives in <see cref="DetailRenderer"/>.
/// </summary>
internal sealed class EncyclopediaWindow : IDisposable
{
    private const int DrawOrder = 965;
    private const double SearchDebounceSeconds = 0.18;

    private static readonly PrefabKind[] SecondaryKinds =
    {
        PrefabKind.Profession,
        PrefabKind.Mission,
        PrefabKind.Submarine,
        PrefabKind.Structure,
        PrefabKind.Upgrade,
        PrefabKind.ItemAssembly,
        PrefabKind.LevelObject,
        PrefabKind.Event
    };

    private readonly PrefabCatalog catalog;
    private readonly UserState state;
    private readonly JebConfig config;
    private readonly Action saveState;
    private readonly DetailRenderer renderer;

    private readonly List<NavigationEntry> history;
    private readonly Dictionary<PrefabKind, GUIButton> filterButtons = new();

    private GUIFrame? overlay;
    private GUIFrame? window;
    private GUIListBox? resultList;
    private GUIListBox? metadataList;
    private GUIFrame? centerPanel;
    private GUITextBox? searchBox;
    private GUITextBlock? resultSummary;
    private GUIButton? backButton;
    private GUIButton? forwardButton;
    private GUIButton? favoriteButton;
    private GUIButton? profileButton;
    private GUIFrame? resizeHandle;
    private GUIDragHandle? dragHandle;

    private WindowProfile profile;
    private CatalogRecord? selected;
    private PrefabKind filter = PrefabKind.All;
    private string activeTab = "overview";
    private string search = string.Empty;
    private string? pendingSearch;
    private double searchTimer;
    private int historyIndex;
    private bool resizing;
    private bool wasDragging;
    private Point resizeStartMouse;
    private Point resizeStartSize;
    private string language;

    public EncyclopediaWindow(
        PrefabCatalog catalog,
        MetadataExtractor metadata,
        CreatureMediaRepository creatureMedia,
        RecipeTrackerHud tracker,
        UserState state,
        JebConfig config,
        Action saveState)
    {
        this.catalog = catalog;
        this.state = state;
        this.config = config;
        this.saveState = saveState;
        history = state.History;
        history.RemoveAll(entry => !catalog.Snapshot.ByKey.ContainsKey(entry.RecordKey));
        historyIndex = Math.Clamp(state.HistoryIndex, -1, history.Count - 1);
        state.HistoryIndex = historyIndex;
        renderer = new DetailRenderer(catalog, metadata, creatureMedia, tracker, SelectRecord);
        profile = BuiltInProfiles.Resolve(state.ActiveProfile, state.CustomProfile);
        language = L.CurrentLanguage;
    }

    public bool IsVisible => overlay is not null;
    public CatalogRecord? Selected => selected;

    public void Toggle()
    {
        if (IsVisible) { Close(); }
        else { Open(); }
    }

    public void Open(CatalogRecord? record = null)
    {
        if (!IsVisible) { BuildGui(); }
        if (record is not null) { SelectRecord(record); }
    }

    public void OpenItem(string identifier)
    {
        CatalogRecord? record = catalog.FindItem(identifier);
        Open(record);
    }

    public void Close()
    {
        CapturePosition();
        DestroyGui();
    }

    public void Update(double deltaTime)
    {
        if (!IsVisible) { return; }

        if (!language.Equals(L.CurrentLanguage, StringComparison.Ordinal))
        {
            language = L.CurrentLanguage;
            string? selectedKey = selected?.Key;
            catalog.Build();
            selected = selectedKey is not null &&
                       catalog.Snapshot.ByKey.TryGetValue(selectedKey, out CatalogRecord? localized)
                ? localized
                : null;
            RebuildGuiPreservingState();
        }

        if (pendingSearch is not null)
        {
            searchTimer -= deltaTime;
            if (searchTimer <= 0)
            {
                search = pendingSearch;
                pendingSearch = null;
                RebuildResults();
            }
        }

        UpdateResize();
        UpdateDragPersistence();
        overlay?.AddToGUIUpdateList(order: DrawOrder);
    }

    public void NavigateBack()
    {
        if (historyIndex <= 0) { return; }
        historyIndex--;
        PersistHistoryCursor();
        RestoreHistory(history[historyIndex]);
    }

    public void NavigateForward()
    {
        if (historyIndex < 0 || historyIndex >= history.Count - 1) { return; }
        historyIndex++;
        PersistHistoryCursor();
        RestoreHistory(history[historyIndex]);
    }

    private void BuildGui()
    {
        profile = BuiltInProfiles.Resolve(state.ActiveProfile, state.CustomProfile);
        overlay = new GUIFrame(
            new RectTransform(Vector2.One, GUI.Canvas, Anchor.Center),
            style: string.Empty)
        {
            Color = JebPalette.Backdrop,
            CanBeFocused = false
        };

        int width = Math.Clamp((int)(GUI.UIWidth * profile.Width), 560, Math.Max(560, GUI.UIWidth - 12));
        int height = Math.Clamp((int)(GameMain.GraphicsHeight * profile.Height), 360,
            Math.Max(360, GameMain.GraphicsHeight - 12));
        var windowTransform = new RectTransform(
            new Point(width, height), overlay.RectTransform, Anchor.TopLeft, Pivot.TopLeft,
            isFixedSize: true)
        {
            MinSize = new Point(Math.Min(560, GUI.UIWidth), Math.Min(360, GameMain.GraphicsHeight)),
            MaxSize = new Point(GUI.UIWidth, GameMain.GraphicsHeight)
        };
        window = new GUIFrame(windowTransform, "CircuitBoxFrame")
        {
            Color = JebPalette.Window,
            CanBeFocused = true,
            Selected = true
        };
        PositionWindow(windowTransform, profile);

        var root = new GUILayoutGroup(
            new RectTransform(new Vector2(0.985f, 0.985f), window.RectTransform, Anchor.Center),
            isHorizontal: false)
        {
            RelativeSpacing = 0.007f,
            Stretch = true
        };
        root.RectTransform.LocalScale = new Vector2(
            Math.Clamp(profile.UiScale, 0.75f, 1.25f));

        BuildHeader(root.RectTransform);
        BuildFamilyBar(root.RectTransform);
        BuildContent(root.RectTransform);

        resizeHandle = new GUIFrame(
            new RectTransform(new Point(24, 24), window.RectTransform, Anchor.BottomRight,
                Pivot.BottomRight, isFixedSize: true),
            "GUIDragIndicator")
        {
            Color = JebPalette.Gold,
            CanBeFocused = true,
            ToolTip = L.Get("profile.hint")
        };

        UpdateNavigationButtons();
        UpdateFavoriteButton();
        RebuildResults();
        RenderSelection();
    }

    private void BuildHeader(RectTransform parent)
    {
        if (window is null) { return; }
        var header = new GUIFrame(new RectTransform(new Vector2(1.0f, 0.075f), parent), "GUIFrameBottom")
        {
            Color = JebPalette.Header
        };
        var layout = new GUILayoutGroup(
            new RectTransform(new Vector2(0.985f, 0.82f), header.RectTransform, Anchor.Center),
            isHorizontal: true,
            childAnchor: Anchor.CenterLeft)
        {
            RelativeSpacing = 0.006f,
            Stretch = true
        };

        backButton = HeaderButton(layout.RectTransform, 0.065f, L.Get("action.back"), () =>
        {
            NavigateBack();
            return true;
        });
        forwardButton = HeaderButton(layout.RectTransform, 0.065f, L.Get("action.forward"), () =>
        {
            NavigateForward();
            return true;
        });

        var title = new GUIFrame(new RectTransform(new Vector2(0.19f, 0.9f), layout.RectTransform), string.Empty);
        Ui.Text(title.RectTransform, L.Get("app.title"), JebPalette.Cream, GUIStyle.SubHeadingFont,
            Alignment.CenterLeft, false, 1.0f, 0.58f, Anchor.TopLeft);
        Ui.Text(title.RectTransform, L.Get("app.subtitle"), JebPalette.Muted, GUIStyle.SmallFont,
            Alignment.CenterLeft, false, 1.0f, 0.35f, Anchor.BottomLeft);

        searchBox = GUI.CreateTextBoxWithPlaceholder(
            new RectTransform(new Vector2(0.285f, 0.82f), layout.RectTransform),
            search,
            L.Get("search.placeholder"));
        searchBox.OnTextChanged += (_, value) =>
        {
            pendingSearch = value;
            searchTimer = SearchDebounceSeconds;
            return true;
        };

        favoriteButton = HeaderButton(layout.RectTransform, 0.085f, L.Get("action.favorite"), ToggleFavorite);
        profileButton = HeaderButton(layout.RectTransform, 0.19f,
            L.F("action.profile", DisplayProfileName(profile.Name)), CycleProfile);
        profileButton.ToolTip = L.Get("profile.hint");
        _ = HeaderButton(layout.RectTransform, 0.07f, L.Get("action.close"), () =>
        {
            Close();
            return true;
        }, "GUICancelButton");

        dragHandle = new GUIDragHandle(
            new RectTransform(Vector2.One, title.RectTransform, Anchor.Center),
            window.RectTransform,
            style: string.Empty)
        {
            CanBeFocused = true,
            DragArea = new Rectangle(0, 0, GUI.UIWidth, GameMain.GraphicsHeight)
        };
    }

    private static GUIButton HeaderButton(
        RectTransform parent,
        float width,
        string caption,
        Func<bool> clicked,
        string style = "GUIButtonSmall")
    {
        var button = Ui.Button(
            new RectTransform(new Vector2(width, 0.8f), parent),
            caption,
            clicked,
            style);
        button.Font = GUIStyle.SmallFont;
        return button;
    }

    private void BuildFamilyBar(RectTransform parent)
    {
        var bar = new GUIFrame(new RectTransform(new Vector2(1.0f, 0.06f), parent), "InnerFrame")
        {
            Color = JebPalette.Panel
        };
        var layout = new GUILayoutGroup(
            new RectTransform(new Vector2(0.99f, 0.82f), bar.RectTransform, Anchor.Center),
            isHorizontal: true,
            childAnchor: Anchor.CenterLeft)
        {
            RelativeSpacing = 0.005f,
            Stretch = true
        };

        filterButtons.Clear();
        foreach (PrefabKind kind in new[]
                 {
                     PrefabKind.All, PrefabKind.Favorite, PrefabKind.Item, PrefabKind.Affliction,
                     PrefabKind.Creature, PrefabKind.Biome, PrefabKind.Talent
                 })
        {
            PrefabKind captured = kind;
            GUIButton button = HeaderButton(layout.RectTransform, 0.118f,
                L.Get(kind.LocalizationKey()), () =>
                {
                    SetFilter(captured);
                    return true;
                });
            filterButtons[kind] = button;
        }

        GUIButton moreButton = HeaderButton(layout.RectTransform, 0.13f, L.Get("action.more"), () =>
        {
            CycleSecondaryKind();
            return true;
        });
        moreButton.ToolTip = L.Get("search.more_kinds");
        UpdateFilterButtons();
    }

    private void BuildContent(RectTransform parent)
    {
        var content = new GUIFrame(new RectTransform(new Vector2(1.0f, 0.845f), parent), string.Empty)
        {
            Color = JebPalette.Panel
        };

        if (profile.MetadataPlacement == MetadataPlacement.Bottom)
        {
            var horizontal = new GUILayoutGroup(new RectTransform(Vector2.One, content.RectTransform), true)
            {
                RelativeSpacing = 0.008f,
                Stretch = true
            };
            BuildIndexPanel(horizontal.RectTransform, profile.IndexRatio);
            var body = new GUILayoutGroup(
                new RectTransform(new Vector2(1.0f - profile.IndexRatio - 0.008f, 1.0f), horizontal.RectTransform),
                false)
            {
                RelativeSpacing = 0.008f,
                Stretch = true
            };
            BuildCenterPanel(body.RectTransform, 1.0f - profile.MetadataRatio - 0.008f);
            BuildMetadataPanel(body.RectTransform, profile.MetadataRatio);
            return;
        }

        var columns = new GUILayoutGroup(new RectTransform(Vector2.One, content.RectTransform), true)
        {
            RelativeSpacing = 0.008f,
            Stretch = true
        };
        BuildIndexPanel(columns.RectTransform, profile.IndexRatio);
        float metadataWidth = profile.MetadataPlacement == MetadataPlacement.Hidden
            ? 0.0f
            : profile.MetadataRatio;
        BuildCenterPanel(columns.RectTransform,
            Math.Max(0.25f, 1.0f - profile.IndexRatio - metadataWidth -
                            (metadataWidth > 0 ? 0.016f : 0.008f)));
        if (metadataWidth > 0) { BuildMetadataPanel(columns.RectTransform, metadataWidth); }
    }

    private void BuildIndexPanel(RectTransform parent, float width)
    {
        var panel = new GUIFrame(new RectTransform(new Vector2(width, 1.0f), parent), "InnerFrame")
        {
            Color = JebPalette.Panel
        };
        var layout = new GUILayoutGroup(new RectTransform(new Vector2(0.97f, 0.97f), panel.RectTransform, Anchor.Center))
        {
            RelativeSpacing = 0.008f,
            Stretch = true
        };
        var heading = new GUIFrame(new RectTransform(new Vector2(1.0f, 0.065f), layout.RectTransform), string.Empty);
        Ui.Text(heading.RectTransform, L.Get("index.title"), JebPalette.Gold, GUIStyle.SmallFont,
            Alignment.CenterLeft, false, 0.58f, 1.0f, Anchor.CenterLeft);
        resultSummary = Ui.Text(heading.RectTransform, string.Empty, JebPalette.Muted, GUIStyle.SmallFont,
            Alignment.CenterRight, false, 0.4f, 1.0f, Anchor.CenterRight);
        resultList = new GUIListBox(new RectTransform(new Vector2(1.0f, 0.925f), layout.RectTransform))
        {
            AutoHideScrollBar = true
        };
    }

    private void BuildCenterPanel(RectTransform parent, float size)
    {
        centerPanel = new GUIFrame(new RectTransform(new Vector2(size, 1.0f), parent), "InnerFrame")
        {
            Color = JebPalette.PanelAlternate
        };
    }

    private void BuildMetadataPanel(RectTransform parent, float size)
    {
        var panel = new GUIFrame(new RectTransform(new Vector2(size, 1.0f), parent), "InnerFrame")
        {
            Color = JebPalette.Panel
        };
        var layout = new GUILayoutGroup(new RectTransform(new Vector2(0.97f, 0.97f), panel.RectTransform, Anchor.Center))
        {
            RelativeSpacing = 0.008f,
            Stretch = true
        };
        var heading = new GUIFrame(new RectTransform(new Vector2(1.0f, 0.065f), layout.RectTransform), string.Empty);
        Ui.Text(heading.RectTransform, L.Get("metadata.title"), JebPalette.Gold, GUIStyle.SmallFont,
            Alignment.CenterLeft, false, 1.0f, 1.0f, Anchor.CenterLeft);
        metadataList = new GUIListBox(new RectTransform(new Vector2(1.0f, 0.925f), layout.RectTransform))
        {
            AutoHideScrollBar = true
        };
    }

    private void SetFilter(PrefabKind kind)
    {
        filter = kind;
        UpdateFilterButtons();
        RebuildResults();
    }

    private void CycleSecondaryKind()
    {
        int current = Array.IndexOf(SecondaryKinds, filter);
        SetFilter(SecondaryKinds[(current + 1) % SecondaryKinds.Length]);
    }

    private void UpdateFilterButtons()
    {
        foreach ((PrefabKind kind, GUIButton button) in filterButtons)
        {
            button.Selected = kind == filter;
            button.TextColor = kind == filter ? JebPalette.Cream : JebPalette.Muted;
        }
    }

    private void RebuildResults()
    {
        if (resultList is null) { return; }
        Ui.Reset(resultList);

        List<CatalogRecord> matches = catalog.Query(filter, search, state.Favorites)
            .OrderByDescending(record => state.Favorites.Contains(record.Key))
            .ThenBy(record => record.Kind)
            .ThenBy(record => record.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
        resultSummary!.Text = L.F("search.results", matches.Count);

        int limit = Math.Clamp(config.PageSize, 25, 500);
        CatalogRecord[] visible = matches.Take(limit).ToArray();
        foreach (IGrouping<PrefabKind, CatalogRecord> group in visible.GroupBy(record => record.Kind))
        {
            PrefabKind capturedKind = group.Key;
            GUIButton separator = Ui.Separator(resultList.Content.RectTransform,
                $"{L.Get(group.Key.LocalizationKey())}  ·  {group.Count()}", () =>
                {
                    SetFilter(capturedKind);
                    return true;
                }, JebPalette.Cyan);
            separator.RectTransform.MinSize = new Point(0, 30);
            separator.ToolTip = L.Get("search.filter_kind");

            foreach (CatalogRecord record in group)
            {
                string secondary = profile.ShowDescriptionsInIndex && !string.IsNullOrWhiteSpace(record.Description)
                    ? record.Description
                    : record.Identifier;
                if (state.Favorites.Contains(record.Key)) { secondary = "◆  " + secondary; }
                GUIButton row = Ui.LinkRow(resultList.Content.RectTransform,
                    record.Name, secondary, record.Icon, () =>
                    {
                        SelectRecord(record);
                        return true;
                    }, state.Favorites.Contains(record.Key) ? JebPalette.Gold : null,
                    profile.ShowDescriptionsInIndex ? 0.095f : 0.072f);
                row.RectTransform.MinSize = new Point(0, profile.ShowDescriptionsInIndex ? 52 : 39);
                row.Selected = selected?.Key.Equals(record.Key, StringComparison.OrdinalIgnoreCase) == true;
                row.ToolTip = $"{record.Kind}: {record.Identifier}\n{record.Description}";
            }
        }

        if (matches.Count == 0)
        {
            GUIFrame empty = Ui.Callout(resultList.Content.RectTransform,
                L.Get("detail.empty.title"), L.Get("search.empty"), JebPalette.Orange, 0.18f);
            empty.RectTransform.MinSize = new Point(0, 92);
        }
        else if (matches.Count > visible.Length)
        {
            GUIFrame more = Ui.Callout(resultList.Content.RectTransform,
                L.Get("action.more"), L.F("search.more", matches.Count - visible.Length), JebPalette.Muted, 0.13f);
            more.RectTransform.MinSize = new Point(0, 68);
        }
        resultList.UpdateScrollBarSize();
    }

    private void SelectRecord(CatalogRecord record) => SelectRecord(record, addHistory: true);

    private bool SelectRecord(CatalogRecord record, bool addHistory)
    {
        selected = record;
        activeTab = "overview";
        if (addHistory)
        {
            if (historyIndex + 1 < history.Count)
            {
                history.RemoveRange(historyIndex + 1, history.Count - historyIndex - 1);
            }
            if (history.LastOrDefault()?.RecordKey.Equals(record.Key, StringComparison.OrdinalIgnoreCase) != true)
            {
                history.Add(new NavigationEntry
                {
                    RecordKey = record.Key,
                    Kind = record.Kind,
                    DetailTab = activeTab,
                    Search = search
                });
            }
            if (history.Count > 100)
            {
                history.RemoveRange(0, history.Count - 100);
            }
            historyIndex = history.Count - 1;
            PersistHistoryCursor();
        }
        UpdateNavigationButtons();
        UpdateFavoriteButton();
        RebuildResults();
        RenderSelection();
        return true;
    }

    private void RestoreHistory(NavigationEntry entry)
    {
        if (!catalog.Snapshot.ByKey.TryGetValue(entry.RecordKey, out CatalogRecord? record)) { return; }
        selected = record;
        activeTab = entry.DetailTab;
        search = entry.Search;
        if (searchBox is not null && !searchBox.Text.Equals(search, StringComparison.Ordinal))
        {
            searchBox.Text = search;
        }
        UpdateNavigationButtons();
        UpdateFavoriteButton();
        RebuildResults();
        RenderSelection();
    }

    private void PersistHistoryCursor()
    {
        state.HistoryIndex = historyIndex;
        saveState();
    }

    private void RenderSelection()
    {
        if (centerPanel is not null)
        {
            centerPanel.RectTransform.ClearChildren();
            renderer.RenderCenter(centerPanel, selected, activeTab, tab =>
            {
                activeTab = tab;
                if (historyIndex >= 0 && historyIndex < history.Count)
                {
                    history[historyIndex].DetailTab = tab;
                }
                saveState();
                RenderSelection();
            });
        }
        if (metadataList is not null)
        {
            renderer.RenderMetadata(metadataList, selected);
        }
    }

    private bool ToggleFavorite()
    {
        if (selected is null) { return false; }
        if (!state.Favorites.Add(selected.Key)) { state.Favorites.Remove(selected.Key); }
        saveState();
        UpdateFavoriteButton();
        RebuildResults();
        return true;
    }

    private void UpdateFavoriteButton()
    {
        if (favoriteButton is null) { return; }
        bool pinned = selected is not null && state.Favorites.Contains(selected.Key);
        favoriteButton.Enabled = selected is not null;
        favoriteButton.Text = L.Get(pinned ? "action.unfavorite" : "action.favorite");
        favoriteButton.TextColor = pinned ? JebPalette.Gold : JebPalette.Text;
    }

    private void UpdateNavigationButtons()
    {
        if (backButton is not null) { backButton.Enabled = historyIndex > 0; }
        if (forwardButton is not null) { forwardButton.Enabled = historyIndex >= 0 && historyIndex < history.Count - 1; }
    }

    private bool CycleProfile()
    {
        var profiles = BuiltInProfiles.All.Select(value => value.Name).Concat(new[] { "Custom" }).ToArray();
        int index = Array.FindIndex(profiles,
            name => name.Equals(state.ActiveProfile, StringComparison.OrdinalIgnoreCase));
        state.ActiveProfile = profiles[(index + 1 + profiles.Length) % profiles.Length];
        saveState();
        RebuildGuiPreservingState();
        return true;
    }

    private void UpdateResize()
    {
        if (window is null || resizeHandle is null) { return; }
        if (!resizing && resizeHandle.Rect.Contains(PlayerInput.MousePosition) &&
            GUI.IsMouseOn(resizeHandle) && PlayerInput.PrimaryMouseButtonDown())
        {
            resizing = true;
            resizeStartMouse = PlayerInput.MousePosition.ToPoint();
            resizeStartSize = window.RectTransform.NonScaledSize;
        }

        if (!resizing) { return; }
        if (PlayerInput.PrimaryMouseButtonHeld())
        {
            Point delta = PlayerInput.MousePosition.ToPoint() - resizeStartMouse;
            int width = Math.Clamp(resizeStartSize.X + delta.X,
                window.RectTransform.MinSize.X, window.RectTransform.MaxSize.X);
            int height = Math.Clamp(resizeStartSize.Y + delta.Y,
                window.RectTransform.MinSize.Y, window.RectTransform.MaxSize.Y);
            window.RectTransform.Resize(new Point(width, height));
        }
        else
        {
            resizing = false;
            CaptureCustomProfile();
        }
    }

    private void UpdateDragPersistence()
    {
        bool dragging = dragHandle?.Dragging == true;
        if (wasDragging && !dragging) { CaptureCustomProfile(); }
        wasDragging = dragging;
    }

    private void CapturePosition()
    {
        if (window is null || !state.ActiveProfile.Equals("Custom", StringComparison.OrdinalIgnoreCase)) { return; }
        CaptureCustomProfile();
    }

    private void CaptureCustomProfile()
    {
        if (window is null) { return; }
        WindowProfile custom = profile.Copy("Custom");
        custom.Width = Math.Clamp(window.Rect.Width / (float)Math.Max(1, GUI.UIWidth), 0.25f, 1.0f);
        custom.Height = Math.Clamp(window.Rect.Height / (float)Math.Max(1, GameMain.GraphicsHeight), 0.25f, 1.0f);
        int roomX = Math.Max(1, GUI.UIWidth - window.Rect.Width);
        int roomY = Math.Max(1, GameMain.GraphicsHeight - window.Rect.Height);
        custom.PositionX = Math.Clamp(window.Rect.X / (float)roomX, 0.0f, 1.0f);
        custom.PositionY = Math.Clamp(window.Rect.Y / (float)roomY, 0.0f, 1.0f);
        state.CustomProfile = custom;
        state.ActiveProfile = "Custom";
        profile = custom;
        if (profileButton is not null)
        {
            profileButton.Text = L.F("action.profile", DisplayProfileName(profile.Name));
        }
        saveState();
    }

    private static void PositionWindow(RectTransform transform, WindowProfile value)
    {
        int roomX = Math.Max(0, GUI.UIWidth - transform.Rect.Width);
        int roomY = Math.Max(0, GameMain.GraphicsHeight - transform.Rect.Height);
        transform.ScreenSpaceOffset = new Point(
            (int)(roomX * Math.Clamp(value.PositionX, 0.0f, 1.0f)),
            (int)(roomY * Math.Clamp(value.PositionY, 0.0f, 1.0f)));
    }

    private static string DisplayProfileName(string name)
        => L.Get("profile." + name.ToLowerInvariant());

    private void RebuildGuiPreservingState()
    {
        if (!IsVisible) { return; }
        DestroyGui();
        BuildGui();
    }

    private void DestroyGui()
    {
        if (overlay is not null) { overlay.RectTransform.Parent = null; }
        overlay = null;
        window = null;
        resultList = null;
        metadataList = null;
        centerPanel = null;
        searchBox = null;
        resultSummary = null;
        backButton = null;
        forwardButton = null;
        favoriteButton = null;
        profileButton = null;
        resizeHandle = null;
        dragHandle = null;
        resizing = false;
        wasDragging = false;
        filterButtons.Clear();
    }

    public void Dispose()
    {
        Close();
        renderer.Dispose();
    }
}
