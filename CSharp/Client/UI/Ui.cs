#nullable enable

using System;
using Barotrauma;
using Microsoft.Xna.Framework;

namespace JustEnoughBaro;

internal static class JebPalette
{
    public static readonly Color Backdrop = new(2, 8, 12, 226);
    public static readonly Color Window = new(8, 20, 25, 252);
    public static readonly Color Header = new(13, 35, 41, 255);
    public static readonly Color Panel = new(12, 28, 33, 248);
    public static readonly Color PanelAlternate = new(17, 39, 44, 247);
    public static readonly Color Row = new(21, 44, 49, 236);
    public static readonly Color RowHover = new(31, 60, 65, 242);
    public static readonly Color Cyan = new(99, 212, 220, 255);
    public static readonly Color Cream = new(235, 224, 188, 255);
    public static readonly Color Gold = new(221, 181, 101, 255);
    public static readonly Color Green = new(128, 207, 150, 255);
    public static readonly Color Orange = new(226, 153, 85, 255);
    public static readonly Color Red = new(220, 98, 94, 255);
    public static readonly Color Muted = new(131, 162, 165, 255);
    public static readonly Color Text = new(216, 224, 211, 255);
    public static readonly Color Divider = new(56, 91, 94, 220);
}

internal static class Ui
{
    public static RectTransform Relative(
        RectTransform parent,
        float width,
        float height,
        Anchor anchor = Anchor.TopLeft,
        Pivot? pivot = null)
        => new(new Vector2(width, height), parent, anchor, pivot);

    public static GUIFrame Frame(
        RectTransform parent,
        float width,
        float height,
        Anchor anchor = Anchor.TopLeft,
        string? style = "InnerFrame",
        Color? color = null,
        Pivot? pivot = null)
    {
        var frame = new GUIFrame(Relative(parent, width, height, anchor, pivot), style ?? string.Empty);
        if (color.HasValue) { frame.Color = color.Value; }
        return frame;
    }

    public static GUITextBlock Text(
        RectTransform parent,
        string value,
        Color? color = null,
        GUIFont? font = null,
        Alignment alignment = Alignment.TopLeft,
        bool wrap = true,
        float width = 1.0f,
        float height = 0.0f,
        Anchor anchor = Anchor.TopLeft)
    {
        var block = new GUITextBlock(
            Relative(parent, width, height, anchor),
            value,
            color ?? JebPalette.Text,
            font ?? GUIStyle.SmallFont,
            alignment,
            wrap,
            string.Empty)
        {
            CanBeFocused = false
        };
        return block;
    }

    public static GUITextBlock Heading(RectTransform parent, string value, bool major = false)
    {
        var heading = Text(
            parent,
            value.ToUpperInvariant(),
            major ? JebPalette.Cream : JebPalette.Gold,
            major ? GUIStyle.SubHeadingFont : GUIStyle.SmallFont,
            Alignment.CenterLeft,
            wrap: true);
        heading.Padding = new Vector4(8, major ? 9 : 6, 6, major ? 7 : 5);
        return heading;
    }

    public static GUIButton Button(
        RectTransform rect,
        string text,
        Func<bool> clicked,
        string style = "GUIButtonSmall",
        Alignment alignment = Alignment.Center)
    {
        var button = new GUIButton(rect, text, alignment, style)
        {
            OnClicked = (_, _) => clicked()
        };
        return button;
    }

    public static GUIButton Separator(
        RectTransform parent,
        string caption,
        Func<bool>? clicked = null,
        Color? accent = null)
    {
        var button = new GUIButton(
            Relative(parent, 1.0f, 0.055f),
            caption.ToUpperInvariant(),
            Alignment.CenterLeft,
            clicked is null ? string.Empty : "GUIButtonSmall")
        {
            Color = JebPalette.Header,
            TextColor = accent ?? JebPalette.Gold,
            HoverTextColor = JebPalette.Cream,
            CanBeFocused = clicked is not null
        };
        button.TextBlock.Padding = new Vector4(10, 0, 8, 0);
        if (clicked is not null) { button.OnClicked = (_, _) => clicked(); }
        return button;
    }

    public static GUIButton LinkRow(
        RectTransform parent,
        string caption,
        string? secondary,
        Sprite? icon,
        Func<bool> clicked,
        Color? color = null,
        float height = 0.075f)
    {
        var button = new GUIButton(
            Relative(parent, 1.0f, height),
            string.Empty,
            Alignment.CenterLeft,
            "ListBoxElement")
        {
            Color = JebPalette.Row,
            HoverColor = JebPalette.RowHover,
            OnClicked = (_, _) => clicked()
        };

        float textWidth = icon is null ? 0.96f : 0.84f;
        if (icon is not null)
        {
            var image = new GUIImage(
                Relative(button.RectTransform, 0.11f, 0.78f, Anchor.CenterLeft),
                icon,
                scaleToFit: true)
            {
                CanBeFocused = false
            };
            image.RectTransform.RelativeOffset = new Vector2(0.015f, 0);
        }

        var title = Text(
            button.RectTransform,
            caption,
            color ?? JebPalette.Cream,
            GUIStyle.SmallFont,
            Alignment.CenterLeft,
            wrap: false,
            width: textWidth,
            height: string.IsNullOrWhiteSpace(secondary) ? 1.0f : 0.52f,
            anchor: icon is null ? Anchor.Center : Anchor.TopRight);
        title.RectTransform.RelativeOffset = icon is null ? new Vector2(0.02f, 0) : new Vector2(-0.01f, 0.07f);

        if (!string.IsNullOrWhiteSpace(secondary))
        {
            var detail = Text(
                button.RectTransform,
                secondary!,
                JebPalette.Muted,
                GUIStyle.SmallFont,
                Alignment.CenterLeft,
                wrap: false,
                width: textWidth,
                height: 0.42f,
                anchor: icon is null ? Anchor.BottomCenter : Anchor.BottomRight);
            detail.RectTransform.RelativeOffset = icon is null ? new Vector2(0.02f, -0.06f) : new Vector2(-0.01f, -0.06f);
        }
        return button;
    }

    public static GUIFrame KeyValue(
        RectTransform parent,
        string key,
        string value,
        Color? valueColor = null,
        int depth = 0)
    {
        var row = Frame(parent, 1.0f, 0.058f, style: "ListBoxElement", color: JebPalette.Row);
        float indent = Math.Min(0.12f, depth * 0.025f);
        var keyText = Text(
            row.RectTransform,
            key,
            JebPalette.Muted,
            GUIStyle.SmallFont,
            Alignment.CenterLeft,
            wrap: false,
            width: Math.Max(0.18f, 0.38f - indent),
            height: 1.0f,
            anchor: Anchor.CenterLeft);
        keyText.RectTransform.RelativeOffset = new Vector2(0.018f + indent, 0);
        var valueText = Text(
            row.RectTransform,
            value,
            valueColor ?? JebPalette.Text,
            GUIStyle.SmallFont,
            Alignment.CenterLeft,
            wrap: true,
            width: 0.58f,
            height: 0.92f,
            anchor: Anchor.CenterRight);
        valueText.RectTransform.RelativeOffset = new Vector2(-0.018f, 0);
        row.ToolTip = string.IsNullOrWhiteSpace(value) ? key : $"{key}\n{value}";
        return row;
    }

    public static GUIFrame Callout(
        RectTransform parent,
        string title,
        string body,
        Color? accent = null,
        float height = 0.13f)
    {
        var card = Frame(parent, 1.0f, height, style: "InnerFrame", color: JebPalette.PanelAlternate);
        var bar = Frame(card.RectTransform, 0.012f, 0.82f, Anchor.CenterLeft, "InnerFrame", accent ?? JebPalette.Cyan);
        bar.RectTransform.RelativeOffset = new Vector2(0.012f, 0);
        var heading = Text(card.RectTransform, title.ToUpperInvariant(), accent ?? JebPalette.Cyan,
            GUIStyle.SmallFont, Alignment.CenterLeft, false, 0.92f, 0.34f, Anchor.TopRight);
        heading.RectTransform.RelativeOffset = new Vector2(-0.02f, 0.08f);
        var description = Text(card.RectTransform, body, JebPalette.Text,
            GUIStyle.SmallFont, Alignment.TopLeft, true, 0.92f, 0.56f, Anchor.BottomRight);
        description.RectTransform.RelativeOffset = new Vector2(-0.02f, -0.06f);
        return card;
    }

    public static void Reset(GUIListBox? list)
    {
        if (list is null) { return; }
        list.Content.ClearChildren();
        list.BarScroll = 0.0f;
        list.UpdateScrollBarSize();
    }
}
