## KOReader patches

<a href="https://koreader.rocks"><img src="https://raw.githubusercontent.com/koreader/koreader.github.io/master/koreader-logo.png" alt="KOReader" width="50%"></a>

### A collection of personal patches for KOReader

### [2-tidy-dict.lua](2-tidy-dict.lua)

This patch renders the dictionary popup more tidily, only showing the "Highlight" and "Translation" buttons (normaly hidden behind few more clicks) and re-draws previous/next arrows with counter in the between.

### Example

<details>
  <summary>Show example</summary>

<img width="400" src="https://github.com/user-attachments/assets/d2b235ca-c73f-4c1e-a124-1c67ece87946">
</details>

### [2-distributed-progress-bar.lua](2-distributed-progress-bar.lua)

This patch distributes the progress bar elements in the footer so that they are equally spaced and justified. Notice that for this patch to work you need to remove the "Dynamic filler" element (generally used to achieve spacing in the footer).

### Example

<details>
  <summary>Show example</summary>

<img width="400" src="https://github.com/user-attachments/assets/3330bfcd-ff6f-4572-b234-bef6b084504e">
</details>

### [2-custom-ui-fonts](2-custom-ui-fonts.lua)

This patch changes the fonts for the general UI menu appearance together with the dictionary body text by hooking into the style css directly. Two new menu entries are introduced to allow the user to select book text, UI and dictionary fonts independently

### Example

<details>
  <summary>Show example</summary>

<img width="400" src="https://github.com/user-attachments/assets/1f8ec946-b588-486f-9beb-5631aa537060">
<img width="400" src="https://github.com/user-attachments/assets/e143d677-53e8-4931-9dbc-81635d5347be">
</details>

### [2-footer-glyphs.lua](2-footer-glyphs.lua)

This patch allows to change the glyphs used as icons for the progress bar elements. Change at your will modifying the source file.
